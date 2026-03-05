from typing import List

from models.transcript_segment import TranscriptSegment
from utils.llm.clients import llm_mini


def _format_recent_segments(segments: List[TranscriptSegment]) -> str:
    if not segments:
        return "None"

    lines = []
    for segment in segments[-8:]:
        speaker = "User" if segment.is_user else "Other"
        lines.append(f"{speaker}: {segment.text.strip()}")
    return "\n".join(lines) if lines else "None"


async def generate_activation_assistant_response(
    trigger_text: str,
    recent_segments: List[TranscriptSegment],
    photo_description: str,
) -> str:
    transcript_context = _format_recent_segments(recent_segments)
    image_context = (
        photo_description.strip() if photo_description and photo_description.strip() else "The image is unclear."
    )

    prompt = f"""
You are Omi's live capture assistant for the OpenClaw MVP.

Respond to the user's activation request using the initial photo description plus the recent transcript.
Rules:
- Ground the answer in the photo description first.
- Be concise and direct.
- If the image is uncertain, say so plainly.
- Do not claim to have completed any backend action.
- Ask at most one short follow-up question if clarification is needed.
- Keep the response to at most 4 sentences.

Activation utterance:
{trigger_text or "What am I looking at?"}

Recent transcript:
{transcript_context}

Initial photo description:
{image_context}
""".strip()

    response = await llm_mini.ainvoke(prompt, config={"max_tokens": 180})
    content = response.content if response is not None else ""
    return content.strip() if isinstance(content, str) else str(content).strip()
