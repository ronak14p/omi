import random
import re
import threading
import uuid
import logging
from datetime import timezone, datetime
from typing import Union, Tuple, List, Optional

from fastapi import HTTPException

from database import redis_db
import database.conversations as conversations_db
import database.notifications as notification_db
import database.users as users_db
import database.tasks as tasks_db
import database.folders as folders_db
import database.calendar_meetings as calendar_db
from database.vector_db import upsert_vector2, update_vector_metadata
from models.conversation import *
from models.conversation import (
    ExternalIntegrationCreateConversation,
    Conversation,
    CreateConversation,
    ConversationSource,
)
from utils.notifications import send_important_conversation_message
from models.conversation import CalendarMeetingContext
from models.other import Person
from models.task import Task, TaskStatus, TaskAction, TaskActionProvider
from models.trend import Trend
from utils.llm.conversation_processing import (
    get_transcript_structure,
    should_discard_conversation,
    get_reprocess_transcript_structure,
    assign_conversation_to_folder,
)
from utils.analytics import record_usage
from utils.llm.usage_tracker import track_usage, Features
from utils.llm.external_integrations import summarize_experience_text
from utils.llm.chat import (
    retrieve_metadata_from_text,
    retrieve_metadata_from_message,
    retrieve_metadata_fields_from_transcript,
    obtain_emotional_message,
)
from utils.llm.external_integrations import get_message_structure
from utils.llm.clients import generate_embedding
from utils.notifications import send_notification
from utils.other.hume import get_hume, HumeJobCallbackModel, HumeJobModelPredictionResponseModel
from utils.retrieval.rag import retrieve_rag_conversation_context
from utils.webhooks import conversation_created_webhook
from utils.other.storage import precache_conversation_audio

logger = logging.getLogger(__name__)


def _get_structured(
    uid: str,
    language_code: str,
    conversation: Union[Conversation, CreateConversation, ExternalIntegrationCreateConversation],
    force_process: bool = False,
    people: List[Person] = None,
) -> Tuple[Structured, bool]:
    try:
        tz = notification_db.get_user_time_zone(uid)

        # Extract calendar context from external_data
        calendar_context = None
        if hasattr(conversation, 'external_data') and conversation.external_data:
            calendar_data = conversation.external_data.get('calendar_meeting_context')
            if calendar_data:
                calendar_context = CalendarMeetingContext(**calendar_data)

        if (
            conversation.source == ConversationSource.workflow
            or conversation.source == ConversationSource.external_integration
        ):
            if conversation.text_source == ExternalIntegrationConversationSource.audio:
                with track_usage(uid, Features.CONVERSATION_STRUCTURE):
                    structured = get_transcript_structure(
                        conversation.text,
                        conversation.started_at,
                        language_code,
                        tz,
                        calendar_meeting_context=calendar_context,
                    )
                return structured, False

            if conversation.text_source == ExternalIntegrationConversationSource.message:
                with track_usage(uid, Features.CONVERSATION_STRUCTURE):
                    structured = get_message_structure(
                        conversation.text, conversation.started_at, language_code, tz, conversation.text_source_spec
                    )
                return structured, False

            if conversation.text_source == ExternalIntegrationConversationSource.other:
                with track_usage(uid, Features.CONVERSATION_STRUCTURE):
                    structured = summarize_experience_text(conversation.text, conversation.text_source_spec)
                return structured, False

            # not supported conversation source
            raise HTTPException(status_code=400, detail=f'Invalid conversation source: {conversation.text_source}')

        transcript_text = conversation.get_transcript(False, people=people)

        # For re-processing, we don't discard, just re-structure.
        if force_process:
            # reprocess endpoint
            with track_usage(uid, Features.CONVERSATION_STRUCTURE):
                structured = get_reprocess_transcript_structure(
                    transcript_text,
                    conversation.started_at,
                    language_code,
                    tz,
                    conversation.structured.title,
                    photos=conversation.photos,
                )
            return structured, False

        # Compute conversation duration for discard heuristics
        duration_seconds = None
        if conversation.started_at and conversation.finished_at:
            duration_seconds = max(0, (conversation.finished_at - conversation.started_at).total_seconds())

        # Determine whether to discard the conversation based on its content (transcript and/or photos).
        with track_usage(uid, Features.CONVERSATION_DISCARD):
            discarded = should_discard_conversation(transcript_text, conversation.photos, duration_seconds)
        if discarded:
            return Structured(emoji=random.choice(['🧠', '🎉'])), True

        # If not discarded, proceed to generate the structured summary from transcript and/or photos.
        with track_usage(uid, Features.CONVERSATION_STRUCTURE):
            structured = get_transcript_structure(
                transcript_text,
                conversation.started_at,
                language_code,
                tz,
                photos=conversation.photos,
                calendar_meeting_context=calendar_context,
            )
        return structured, False
    except Exception as e:
        logger.error(e)
        raise HTTPException(status_code=500, detail="Error processing conversation, please try again later")


def _get_conversation_obj(
    uid: str,
    structured: Structured,
    conversation: Union[Conversation, CreateConversation, ExternalIntegrationCreateConversation],
):
    discarded = structured.title == ''
    if isinstance(conversation, CreateConversation):
        conversation_dict = conversation.dict()
        # Store calendar context in external_data if available
        calendar_context = conversation_dict.pop('calendar_meeting_context', None)

        # Use started_at as created_at for imported conversations to preserve original timestamp
        created_at = conversation.started_at if conversation.started_at else datetime.now(timezone.utc)
        conversation = Conversation(
            id=str(uuid.uuid4()),
            uid=uid,
            structured=structured,
            created_at=created_at,
            discarded=discarded,
            **conversation_dict,
        )

        # Add calendar metadata to external_data
        if calendar_context:
            if not conversation.external_data:
                conversation.external_data = {}
            conversation.external_data['calendar_meeting_context'] = calendar_context

        if conversation.photos:
            conversations_db.store_conversation_photos(uid, conversation.id, conversation.photos)
    elif isinstance(conversation, ExternalIntegrationCreateConversation):
        create_conversation = conversation
        # Use started_at as created_at for external integrations to preserve original timestamp
        created_at = conversation.started_at if conversation.started_at else datetime.now(timezone.utc)
        conversation = Conversation(
            id=str(uuid.uuid4()),
            **conversation.dict(),
            created_at=created_at,
            structured=structured,
            discarded=discarded,
        )
        conversation.external_data = create_conversation.dict()
        conversation.app_id = create_conversation.app_id
    else:
        conversation.structured = structured
        conversation.discarded = discarded

    return conversation


def _trigger_apps(
    uid: str,
    conversation: Conversation,
    is_reprocess: bool = False,
    language_code: str = 'en',
    people: List[Person] = None,
):
    # App-store summarization execution is removed in single-agent mode.
    del uid, is_reprocess, language_code, people
    conversation.apps_results = []


def save_structured_vector(uid: str, conversation: Conversation, update_only: bool = False):
    vector = generate_embedding(str(conversation.structured)) if not update_only else None
    tz = notification_db.get_user_time_zone(uid)

    metadata = {}

    # Extract metadata based on conversation source
    if conversation.source == ConversationSource.external_integration:
        text_source = conversation.external_data.get('text_source')
        text_content = conversation.external_data.get('text')
        if text_content and len(text_content) > 0 and text_content and len(text_content) > 0:
            text_source_spec = conversation.external_data.get('text_source_spec')
            if text_source == ExternalIntegrationConversationSource.message.value:
                metadata = retrieve_metadata_from_message(
                    uid, conversation.created_at, text_content, tz, text_source_spec
                )
            elif text_source == ExternalIntegrationConversationSource.other.value:
                metadata = retrieve_metadata_from_text(uid, conversation.created_at, text_content, tz, text_source_spec)
    else:
        # For regular conversations with transcript segments
        segments = [t.dict() for t in conversation.transcript_segments]
        metadata = retrieve_metadata_fields_from_transcript(
            uid, conversation.created_at, segments, tz, photos=conversation.photos
        )

    metadata['created_at'] = int(conversation.created_at.timestamp())

    if not update_only:
        logger.info('save_structured_vector creating vector')
        upsert_vector2(uid, conversation, vector, metadata)
    else:
        logger.info('save_structured_vector updating metadata')
        update_vector_metadata(uid, conversation.id, metadata)


def process_conversation(
    uid: str,
    language_code: str,
    conversation: Union[Conversation, CreateConversation, ExternalIntegrationCreateConversation],
    force_process: bool = False,
    is_reprocess: bool = False,
) -> Conversation:
    # Fetch meeting context from Firestore if meeting_id is associated with this conversation
    if hasattr(conversation, 'id') and conversation.id:
        meeting_id = redis_db.get_conversation_meeting_id(conversation.id)
        if meeting_id:
            try:
                meeting_data = calendar_db.get_meeting(uid, meeting_id)
                if meeting_data:
                    # Add meeting context to conversation's external_data
                    if not hasattr(conversation, 'external_data') or not conversation.external_data:
                        conversation.external_data = {}
                    conversation.external_data['calendar_meeting_context'] = meeting_data
                    logger.info(
                        f"Retrieved meeting context for conversation {conversation.id}: {meeting_data.get('title')}"
                    )
            except Exception as e:
                logger.error(f"Error retrieving meeting context for conversation {conversation.id}: {e}")

    person_ids = conversation.get_person_ids()
    people = []
    if person_ids:
        people_data = users_db.get_people_by_ids(uid, list(set(person_ids)))
        people = [Person(**p) for p in people_data]

    structured, discarded = _get_structured(uid, language_code, conversation, force_process, people=people)
    conversation = _get_conversation_obj(uid, structured, conversation)

    # AI-based folder assignment
    assigned_folder_id = None
    if not discarded and not is_reprocess and not conversation.folder_id:
        try:
            # Get user's folders
            user_folders = folders_db.get_folders(uid)
            if not user_folders:
                user_folders = folders_db.initialize_system_folders(uid)

            if user_folders and conversation.structured:
                with track_usage(uid, Features.CONVERSATION_FOLDER):
                    folder_id, confidence, reasoning = assign_conversation_to_folder(
                        title=conversation.structured.title or '',
                        overview=conversation.structured.overview or '',
                        category=(
                            conversation.structured.category.value if conversation.structured.category else 'other'
                        ),
                        user_folders=user_folders,
                    )
                if folder_id:
                    conversation.folder_id = folder_id
                    assigned_folder_id = folder_id
                    logger.info(
                        f"AI assigned conversation {conversation.id} to folder {folder_id} (confidence: {confidence:.2f}): {reasoning}"
                    )
        except Exception as e:
            logger.error(f"Error during folder assignment for conversation {conversation.id}: {e}")

    if not discarded:
        # Analytics tracking
        insights_gained = 0
        if conversation.structured:
            # Count sentences with more than 5 words from title and overview
            for text in [conversation.structured.title, conversation.structured.overview]:
                if text:
                    sentences = re.split(r'[.!?]+', text)
                    for sentence in sentences:
                        if len(sentence.split()) > 5:
                            insights_gained += 1

            # Count number of action items and events
            insights_gained += len(conversation.structured.action_items)
            insights_gained += len(conversation.structured.events)

        # Count sentences with more than 5 words from app results
        for app_result in conversation.apps_results:
            if app_result.content:
                sentences = re.split(r'[.!?]+', app_result.content)
                for sentence in sentences:
                    if len(sentence.split()) > 5:
                        insights_gained += 1

        if insights_gained > 0:
            record_usage(uid, insights_gained=insights_gained)

        _trigger_apps(uid, conversation, is_reprocess=is_reprocess, language_code=language_code, people=people)
        (
            threading.Thread(
                target=save_structured_vector,
                args=(
                    uid,
                    conversation,
                ),
            ).start()
            if not is_reprocess
            else None
        )

    # Create audio files from chunks if private cloud sync was enabled
    if not is_reprocess and conversation.private_cloud_sync_enabled:
        try:
            audio_files = conversations_db.create_audio_files_from_chunks(uid, conversation.id)
            if audio_files:
                conversation.audio_files = audio_files
                conversations_db.update_conversation(
                    uid, conversation.id, {'audio_files': [af.dict() for af in audio_files]}
                )
                # Pre-cache audio files in background
                precache_conversation_audio(uid, conversation.id, [af.dict() for af in audio_files])
        except Exception as e:
            logger.error(f"Error creating audio files: {e}")

    conversation.status = ConversationStatus.completed
    conversations_db.upsert_conversation(uid, conversation.dict())

    # Update folder conversation count after conversation is saved
    if assigned_folder_id:
        folders_db.update_folder_conversation_count(uid, assigned_folder_id)

    if not is_reprocess:
        threading.Thread(
            target=conversation_created_webhook,
            args=(
                uid,
                conversation,
            ),
        ).start()
        # Disable important conversation for now
        # Send important conversation notification for long conversations (>30 minutes)
        # threading.Thread(
        #     target=_send_important_conversation_notification_if_needed,
        #     args=(uid, conversation),
        # ).start()

    # TODO: trigger external integrations here too

    logger.info(f'process_conversation completed conversation.id= {conversation.id}')
    return conversation


def _send_important_conversation_notification_if_needed(uid: str, conversation: Conversation):
    """
    Send notification for long conversations (>30 minutes) that just completed.
    Only sends once per conversation using Redis deduplication.
    """

    # Skip if conversation is discarded
    if conversation.discarded:
        return

    # Check if we have valid timestamps to compute duration
    if not conversation.started_at or not conversation.finished_at:
        logger.error(f"Cannot compute duration for conversation {conversation.id}: missing timestamps")
        return

    # Calculate duration in seconds
    duration_seconds = (conversation.finished_at - conversation.started_at).total_seconds()

    # Only notify for conversations longer than 30 minutes (1800 seconds)
    if duration_seconds < 1800:
        return

    # Check if notification was already sent for this conversation
    if redis_db.has_important_conversation_notification_been_sent(uid, conversation.id):
        logger.info(f"Important conversation notification already sent for {conversation.id}")
        return

    # Mark as sent before sending to prevent duplicates
    redis_db.set_important_conversation_notification_sent(uid, conversation.id)

    # Send the notification
    logger.info(
        f"Sending important conversation notification for {conversation.id} (duration: {duration_seconds/60:.1f} mins)"
    )
    send_important_conversation_message(uid, conversation.id)


def process_user_emotion(uid: str, language_code: str, conversation: Conversation, urls: [str]):
    logger.info(f'process_user_emotion conversation.id= {conversation.id}')

    # save task
    now = datetime.now()
    task = Task(
        id=str(uuid.uuid4()),
        action=TaskAction.HUME_MERSURE_USER_EXPRESSION,
        user_uid=uid,
        memory_id=conversation.id,
        created_at=now,
        status=TaskStatus.PROCESSING,
    )
    tasks_db.create(task.dict())

    # emotion
    ok = get_hume().request_user_expression_mersurement(urls)
    if "error" in ok:
        err = ok["error"]
        logger.error(err)
        return
    job = ok["result"]
    request_id = job.id
    if not request_id or len(request_id) == 0:
        logger.info(f"Can not request users feeling. uid: {uid}")
        return

    # update task
    task.request_id = request_id
    task.updated_at = datetime.now()
    tasks_db.update(task.id, task.dict())

    return


def process_user_expression_measurement_callback(provider: str, request_id: str, callback: HumeJobCallbackModel):
    support_providers = [TaskActionProvider.HUME]
    if provider not in support_providers:
        logger.info(f"Provider is not supported. {provider}")
        return

    # Get task
    task_action = ""
    if provider == TaskActionProvider.HUME:
        task_action = TaskAction.HUME_MERSURE_USER_EXPRESSION
    if len(task_action) == 0:
        logger.info("Task action is empty")
        return

    task_data = tasks_db.get_task_by_action_request(task_action, request_id)
    if task_data is None:
        logger.warning(f"Task not found. Action: {task_action}, Request ID: {request_id}")
        return

    task = Task(**task_data)

    # Update
    task_status = task.status
    if callback.status == "COMPLETED":
        task_status = TaskStatus.DONE
    elif callback.status == "FAILED":
        task_status = TaskStatus.ERROR
    else:
        logger.info(f"Not support status {callback.status}")
        return

    # Not changed
    if task_status == task.status:
        logger.info("Task status are synced")
        return

    task.status = task_status
    task.updated_at = datetime.now()
    tasks_db.update(task.id, task.dict())

    # done or not
    if task.status != TaskStatus.DONE:
        logger.info(f"Task is not done yet. Uid: {task.user_uid}, task_id: {task.id}, status: {task.status}")
        return

    uid = task.user_uid

    # Save predictions
    if len(callback.predictions) > 0:
        conversations_db.store_model_emotion_predictions_result(
            task.user_uid, task.memory_id, provider, callback.predictions
        )

    # Conversation
    conversation_data = conversations_db.get_conversation(uid, task.memory_id)
    if conversation_data is None:
        logger.warning(f"Conversation is not found. Uid: {uid}. Conversation: {task.memory_id}")
        return

    conversation = Conversation(**conversation_data)

    # Get prediction
    predictions = callback.predictions
    logger.info(predictions)
    if len(predictions) == 0 or len(predictions[0].emotions) == 0:
        logger.info(f"Can not predict user's expression. Uid: {uid}")
        return

    # Filter users emotions only
    users_frames = []
    for seg in filter(lambda seg: seg.is_user and 0 <= seg.start < seg.end, conversation.transcript_segments):
        users_frames.append((seg.start, seg.end))
    # print(users_frames)

    if len(users_frames) == 0:
        logger.info(f"User time frames are empty. Uid: {uid}")
        return

    users_predictions = []
    for prediction in predictions:
        for uf in users_frames:
            logger.info(f"{uf} {prediction.time}")
            if uf[0] <= prediction.time[0] and prediction.time[1] <= uf[1]:
                users_predictions.append(prediction)
                break
    if len(users_predictions) == 0:
        logger.info(f"Predictions are filtered by user transcript segments. Uid: {uid}")
        return

    # Top emotions
    emotion_filters = []
    user_emotions = []
    for up in users_predictions:
        user_emotions += up.emotions
    emotions = HumeJobModelPredictionResponseModel.get_top_emotion_names(user_emotions, 1, 0.5)
    # print(emotions)
    if len(emotion_filters) > 0:
        emotions = filter(lambda emotion: emotion in emotion_filters, emotions)
    if len(emotions) == 0:
        logger.info(f"Can not extract users emmotion. uid: {uid}")
        return

    emotion = ','.join(emotions)
    logger.info(f"Emotion Uid: {uid} {emotion}")

    # Ask llms about notification content
    title = "omi"
    context_str, _ = retrieve_rag_conversation_context(uid, conversation)

    response: str = obtain_emotional_message(uid, conversation, context_str, emotion)
    message = response

    # Send the notification
    send_notification(uid, title, message, None)

    return


def retrieve_in_progress_conversation(uid):
    conversation_id = redis_db.get_in_progress_conversation_id(uid)
    existing = None

    if conversation_id:
        existing = conversations_db.get_conversation(uid, conversation_id)
        if existing and existing['status'] != 'in_progress':
            existing = None

    if not existing:
        existing = conversations_db.get_in_progress_conversation(uid)
    return existing
