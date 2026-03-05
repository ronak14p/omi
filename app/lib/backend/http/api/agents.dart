import 'dart:convert';

import 'package:omi/backend/http/shared.dart';
import 'package:omi/backend/schema/agent.dart';
import 'package:omi/env/env.dart';
import 'package:omi/utils/logger.dart';

Future<AgentVmInfo?> getAgentVmStatus() async {
  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v1/agent/vm-status',
    headers: {},
    method: 'GET',
    body: '',
  );
  if (response == null) return null;
  if (response.statusCode == 200) {
    return AgentVmInfo.fromJson(jsonDecode(response.body));
  }
  return null;
}

Future<void> ensureAgentVm() async {
  try {
    await makeApiCall(
      url: '${Env.apiBaseUrl}v1/agent/vm-ensure',
      headers: {},
      method: 'POST',
      body: '',
    );
  } catch (e) {
    Logger.debug('ensureAgentVm failed: $e');
  }
}

Future<void> sendAgentKeepalive() async {
  try {
    await makeApiCall(
      url: '${Env.apiBaseUrl}v1/agent/keepalive',
      headers: {},
      method: 'POST',
      body: '',
    );
  } catch (e) {
    Logger.debug('sendAgentKeepalive failed: $e');
  }
}

Future<AgentActionState?> proposeAgentAction({
  required String interactionId,
  required String summary,
  List<String> proposedTools = const [],
  bool requiresConfirmation = true,
}) async {
  final response = await makeApiCall(
    url: '${Env.apiBaseUrl}v1/agent/actions/propose',
    headers: {},
    method: 'POST',
    body: jsonEncode({
      'interaction_id': interactionId,
      'summary': summary,
      'proposed_tools': proposedTools,
      'requires_confirmation': requiresConfirmation,
    }),
  );
  if (response == null || response.statusCode != 200) {
    return null;
  }
  return AgentActionState.fromJson(jsonDecode(response.body));
}

Future<AgentActionState?> confirmAgentAction({
  required String interactionId,
  required bool approved,
}) async {
  final response = await makeApiCall(
    url: '${Env.apiBaseUrl}v1/agent/actions/confirm',
    headers: {},
    method: 'POST',
    body: jsonEncode({
      'interaction_id': interactionId,
      'decision': approved ? 'yes' : 'no',
    }),
  );
  if (response == null || response.statusCode != 200) {
    return null;
  }

  final body = jsonDecode(response.body);
  return AgentActionState(
    interactionId: body['interaction_id'] ?? interactionId,
    status: body['status'] ?? '',
    lastDecision: body['decision'],
  );
}

Future<AgentActionState?> getAgentActionState(String interactionId) async {
  final response = await makeApiCall(
    url: '${Env.apiBaseUrl}v1/agent/actions/$interactionId',
    headers: {},
    method: 'GET',
    body: '',
  );
  if (response == null || response.statusCode != 200) {
    return null;
  }

  final body = jsonDecode(response.body);
  if (body['has_action'] != true || body['action'] == null) {
    return null;
  }
  return AgentActionState.fromJson(body['action']);
}
