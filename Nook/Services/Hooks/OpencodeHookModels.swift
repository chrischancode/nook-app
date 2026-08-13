//
//  OpencodeHookModels.swift
//  Nook
//
//  OpenCode bus event envelope and the narrow Nook event surface.
//
//  The plugin (Resources/opencode-plugin/index.js) forwards every bus
//  event with `origin: "opencode"`.  We decode the socket payload into
//  OpencodeHookEnvelope and then let the adapter filter + normalise
//  into OpencodeSessionEvent — only the 5 events Nook tracks.
//

import Foundation

/// Raw envelope received from the Nook OpenCode plugin over the Unix socket.
struct OpencodeHookEnvelope: Decodable, Sendable {
    let origin: String
    let type: String
    let properties: [String: AnyCodable]?
}

/// Normalised event surface — the only OpenCode events Nook currently cares about.
///
/// Mirrors CodexSessionEvent so the two integrations share the same
/// session-tracking machinery inside SessionStore.
///
/// `messageId` on chat-item-producing events (assistantThinking/Text, preTool,
/// postTool, userPromptSubmitted) carries the opencode message ID for use by
/// OpencodeChatItemAdapter's BlockOrdering. It is optional with a default of
/// nil so existing call sites continue to compile without changes.
enum OpencodeSessionEvent: Sendable {
    case sessionStart(sessionId: String, cwd: String)
    case userPromptSubmitted(sessionId: String, cwd: String, prompt: String?, messageId: String? = nil)
    case processingStarted(sessionId: String, cwd: String)
    case waitingForUserInput(sessionId: String, cwd: String)
    case assistantThinking(sessionId: String, cwd: String, text: String, messageId: String? = nil)
    case assistantText(sessionId: String, cwd: String, text: String, messageId: String? = nil)
    case preTool(sessionId: String, cwd: String, toolName: String, toolUseId: String?, inputSummary: String?, input: [String: String] = [:], messageId: String? = nil)
    case postTool(sessionId: String, cwd: String, toolName: String, toolUseId: String?, inputSummary: String?, output: String? = nil, error: String? = nil, messageId: String? = nil)
    case image(sessionId: String, cwd: String, mediaType: String, base64Data: String, messageId: String? = nil)
    case permissionAsked(sessionId: String, cwd: String, requestId: String, toolName: String, toolUseId: String?, input: [String: String], inputSummary: String?, alwaysPatterns: [String])
    case serverPortReceived(sessionId: String, port: Int, version: String?)
    case stop(sessionId: String, cwd: String)
    // MARK: - Subagent events
    // All subagent events are scoped to the PARENT session — the adapter
    // already rewrites child session ids before emitting these. Subagent
    // tool events carry the call id from the child's message stream (kept
    // as the subagent tool id) so postTool status updates can correlate.
    case subagentStarted(sessionId: String, taskToolId: String)
    case subagentToolExecuted(sessionId: String, tool: SubagentToolCall)
    case subagentToolCompleted(sessionId: String, toolId: String, status: ToolStatus)
    case subagentStopped(sessionId: String, taskToolId: String)
}
