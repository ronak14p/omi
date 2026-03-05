class AgentVmInfo {
  final bool hasVm;
  final String? ip;
  final String? authToken;
  final String? status;

  AgentVmInfo({
    required this.hasVm,
    this.ip,
    this.authToken,
    this.status,
  });

  factory AgentVmInfo.fromJson(Map<String, dynamic> json) {
    return AgentVmInfo(
      hasVm: json['has_vm'] ?? false,
      ip: json['ip'],
      authToken: json['auth_token'],
      status: json['status'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'has_vm': hasVm,
      'ip': ip,
      'auth_token': authToken,
      'status': status,
    };
  }
}

class AgentActionState {
  final String interactionId;
  final String status;
  final String? summary;
  final List<String> proposedTools;
  final bool requiresConfirmation;
  final String? lastDecision;

  AgentActionState({
    required this.interactionId,
    required this.status,
    this.summary,
    this.proposedTools = const [],
    this.requiresConfirmation = true,
    this.lastDecision,
  });

  factory AgentActionState.fromJson(Map<String, dynamic> json) {
    return AgentActionState(
      interactionId: json['interaction_id'] ?? '',
      status: json['status'] ?? '',
      summary: json['summary'],
      proposedTools: (json['proposed_tools'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      requiresConfirmation: json['requires_confirmation'] ?? true,
      lastDecision: json['last_decision'],
    );
  }
}
