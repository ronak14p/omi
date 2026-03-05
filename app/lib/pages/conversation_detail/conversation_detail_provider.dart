import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_provider_utilities/flutter_provider_utilities.dart';

import 'package:omi/backend/http/api/audio.dart';
import 'package:omi/backend/http/api/conversations.dart';
import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/backend/schema/structured.dart';
import 'package:omi/backend/schema/transcript_segment.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/utils/analytics/mixpanel.dart';
import 'package:omi/utils/logger.dart';
import 'package:omi/utils/platform/platform_manager.dart';

class ConversationDetailProvider extends ChangeNotifier with MessageNotifierMixin {
  ConversationProvider? conversationProvider;

  // late ServerConversation memory;

  DateTime selectedDate = DateTime.now();
  String? _cachedConversationId;

  bool isLoading = false;
  bool loadingReprocessConversation = false;
  String reprocessConversationId = '';

  final scaffoldKey = GlobalKey<ScaffoldState>();

  Structured get structured {
    return conversation.structured;
  }

  ServerConversation? _cachedConversation;
  ServerConversation get conversation {
    final list = conversationProvider?.groupedConversations[selectedDate];
    final id = _cachedConversationId;

    ServerConversation? result;

    if (list != null && list.isNotEmpty) {
      if (id != null) {
        result = list.firstWhereOrNull((c) => c.id == id);
      }
      result ??= list.first;
      _cachedConversationId = result.id;
    }

    result ??= _cachedConversation;
    if (result != null &&
        result.createdAt.year == selectedDate.year &&
        result.createdAt.month == selectedDate.month &&
        result.createdAt.day == selectedDate.day) {
      return _cachedConversation = result;
    }

    throw StateError("No valid conversation found");
  }

  List<bool> appResponseExpanded = [];

  TextEditingController? titleController;
  FocusNode? titleFocusNode;

  bool isTranscriptExpanded = false;

  bool canDisplaySeconds = true;

  bool hasAudioRecording = false;

  bool editSegmentLoading = false;

  bool showUnassignedFloatingButton = true;

  void toggleEditSegmentLoading(bool value) {
    editSegmentLoading = value;
    notifyListeners();
  }

  void setShowUnassignedFloatingButton(bool value) {
    showUnassignedFloatingButton = value;
    notifyListeners();
  }

  Future<void> saveEditingSegmentText(int segmentIndex, String newText) async {
    final segment = conversation.transcriptSegments[segmentIndex];
    final oldText = segment.text;

    if (newText.trim().isEmpty || newText.trim() == oldText) return;

    // Optimistic update
    segment.text = newText.trim();
    notifyListeners();

    final success = await updateConversationSegmentText(conversation.id, segment.id, newText.trim());
    if (!success && !_isDisposed) {
      conversation.transcriptSegments[segmentIndex].text = oldText;
      notifyListeners();
    }
  }

  void toggleIsTranscriptExpanded() {
    isTranscriptExpanded = !isTranscriptExpanded;
    notifyListeners();
  }

  void setProviders(ConversationProvider conversationProvider) {
    this.conversationProvider = conversationProvider;
    notifyListeners();
  }

  updateLoadingState(bool loading) {
    isLoading = loading;
    notifyListeners();
  }

  updateReprocessConversationLoadingState(bool loading) {
    loadingReprocessConversation = loading;
    notifyListeners();
  }

  void updateReprocessConversationId(String id) {
    reprocessConversationId = id;
    notifyListeners();
  }

  void updateConversation(String conversationId, DateTime date) {
    final list = conversationProvider?.groupedConversations[date];
    if (list != null) {
      final conv = list.firstWhereOrNull((c) => c.id == conversationId);
      if (conv != null) {
        selectedDate = date;
        _cachedConversationId = conv.id;
        _cachedConversation = conv;
        appResponseExpanded = List.filled(conv.appResults.length, false);
        notifyListeners();
      }
    }
  }

  void updateEventState(bool state, int i) {
    conversation.structured.events[i].created = state;
    notifyListeners();
  }

  void updateActionItemState(bool state, int i) {
    conversation.structured.actionItems[i].completed = state;
    notifyListeners();
  }

  List<ActionItem> deletedActionItems = [];

  void deleteActionItem(int i) {
    deletedActionItems.add(conversation.structured.actionItems[i]);
    conversation.structured.actionItems.removeAt(i);
    notifyListeners();
  }

  void undoDeleteActionItem(int idx) {
    conversation.structured.actionItems.insert(idx, deletedActionItems.removeLast());
    notifyListeners();
  }

  void deleteActionItemPermanently(ActionItem item, int itemIdx) {
    deletedActionItems.removeWhere((element) => element == item);
    deleteConversationActionItem(conversation.id, item);
    notifyListeners();
  }

  void updateAppResponseExpanded(int index) {
    appResponseExpanded[index] = !appResponseExpanded[index];
    notifyListeners();
  }

  bool hasConversationSummaryRatingSet = false;
  Timer? _ratingTimer;
  bool showRatingUI = false;

  void setShowRatingUi(bool value) {
    showRatingUI = value;
    notifyListeners();
  }

  void setConversationRating(int value) {
    setConversationSummaryRating(conversation.id, value);
    hasConversationSummaryRatingSet = true;
    setShowRatingUi(false);
  }

  Future initConversation() async {
    // updateLoadingState(true);
    titleController?.dispose();
    titleFocusNode?.dispose();
    _ratingTimer?.cancel();
    showRatingUI = false;
    hasConversationSummaryRatingSet = false;

    titleController = TextEditingController();
    titleFocusNode = FocusNode();

    showUnassignedFloatingButton = true;

    titleController!.text = conversation.structured.title;
    titleFocusNode!.addListener(() {
      print('titleFocusNode focus changed');
      if (!titleFocusNode!.hasFocus) {
        conversation.structured.title = titleController!.text;
        updateConversationTitle(conversation.id, titleController!.text);
      }
    });

    canDisplaySeconds = TranscriptSegment.canDisplaySeconds(conversation.transcriptSegments);

    // Pre-cache audio files in background
    if (conversation.hasAudio()) {
      precacheConversationAudio(conversation.id);
    }

    if (!conversation.discarded) {
      getHasConversationSummaryRating(conversation.id).then((value) {
        if (_isDisposed) return;
        hasConversationSummaryRatingSet = value;
        notifyListeners();
        if (!hasConversationSummaryRatingSet) {
          _ratingTimer = Timer(const Duration(seconds: 15), () {
            if (_isDisposed) return;
            setConversationSummaryRating(conversation.id, -1); // set -1 to indicate is was shown
            showRatingUI = true;
            notifyListeners();
          });
        }
      });
    }

    // updateLoadingState(false);
    notifyListeners();
  }

  Future<bool> reprocessConversation({String? appId}) async {
    Logger.debug('_reProcessConversation with appId: $appId');
    updateReprocessConversationLoadingState(true);
    updateReprocessConversationId(conversation.id);
    try {
      var updatedConversation = await reProcessConversationServer(conversation.id, appId: appId);
      if (_isDisposed) return false;
      MixpanelManager().reProcessConversation(conversation);
      updateReprocessConversationLoadingState(false);
      updateReprocessConversationId('');
      if (updatedConversation == null) {
        notifyError('REPROCESS_FAILED');
        notifyListeners();
        return false;
      }

      // else
      conversationProvider!.updateConversation(updatedConversation);
      SharedPreferencesUtil().modifiedConversationDetails = updatedConversation;

      // Update the cached conversation to ensure we have the latest data
      _cachedConversation = updatedConversation;
      notifyInfo('REPROCESS_SUCCESS');
      notifyListeners();
      return true;
    } catch (err, stacktrace) {
      print(err);
      var conversationReporting = MixpanelManager().getConversationEventProperties(conversation);
      await PlatformManager.instance.crashReporter.reportCrash(err, stacktrace, userAttributes: {
        'conversation_transcript_length': conversationReporting['transcript_length'].toString(),
        'conversation_transcript_word_count': conversationReporting['transcript_word_count'].toString(),
      });
      notifyError('REPROCESS_FAILED');
      updateReprocessConversationLoadingState(false);
      updateReprocessConversationId('');
      notifyListeners();
      return false;
    }
  }

  void unassignConversationTranscriptSegment(String conversationId, String segmentId) {
    final segmentIdx = conversation.transcriptSegments.indexWhere((s) => s.id == segmentId);
    if (segmentIdx == -1) return;
    conversation.transcriptSegments[segmentIdx].isUser = false;
    conversation.transcriptSegments[segmentIdx].personId = null;
    assignBulkConversationTranscriptSegments(conversationId, [segmentId]);
    notifyListeners();
  }

  /// Returns the first app result from the conversation if available
  /// This is typically the summary of the conversation
  AppResponse? getSummarizedApp() {
    if (conversation.appResults.isNotEmpty) {
      return conversation.appResults[0];
    }
    // If no appResults but we have structured overview, create a fake AppResponse
    if (conversation.structured.overview.isNotEmpty) {
      return AppResponse(
        conversation.structured.overview,
        appId: null,
      );
    }
    return null;
  }

  void setCachedConversation(ServerConversation conversation) {
    _cachedConversation = conversation;
    _cachedConversationId = conversation.id;
    notifyListeners();
  }

  Future<void> refreshConversation() async {
    try {
      final updatedConversation = await getConversationById(conversation.id);
      if (_isDisposed) return;
      if (updatedConversation != null) {
        _cachedConversation = updatedConversation;
        conversationProvider?.updateConversation(updatedConversation);
        notifyListeners();
      }
    } catch (e) {
      Logger.debug('Error refreshing conversation: $e');
    }
  }

  void updateFolderIdLocally(String? newFolderId) {
    if (_cachedConversation != null) {
      _cachedConversation!.folderId = newFolderId;
      conversationProvider?.updateConversation(_cachedConversation!);
      notifyListeners();
    }
  }

  void updateVisibilityLocally(ConversationVisibility newVisibility) {
    if (_cachedConversation != null) {
      _cachedConversation!.visibility = newVisibility;
      conversationProvider?.updateConversation(_cachedConversation!);
      notifyListeners();
    }
  }

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    _ratingTimer?.cancel();
    super.dispose();
  }
}
