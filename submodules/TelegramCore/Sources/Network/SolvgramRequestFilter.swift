import Foundation
import SGSimpleSettings

// MARK: Solvgram — requests the Solvgram menu keeps from reaching the server.
// A filtered request is answered locally with the TL bytes of a successful, empty result, so the
// caller carries on as if the server had accepted it (the local read mark still moves, a queued
// operation is still confirmed). This is the Lead tweak's request filter (FunctionHandler.m),
// keyed by method name instead of constructor id so a layer change cannot silently break it.

private func tlInt32(_ value: UInt32) -> [UInt8] {
    return [UInt8(value & 0xff), UInt8((value >> 8) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 24) & 0xff)]
}

// boolTrue#997275b5 = Bool
private let tlBoolTrue = Data(tlInt32(0x997275b5))
// messages.affectedMessages#84d19185 pts:int pts_count:int
private let tlAffectedMessagesEmpty = Data(tlInt32(0x84d19185) + tlInt32(0) + tlInt32(0))
// vector#1cb5c415 of zero elements
private let tlEmptyVector = Data(tlInt32(0x1cb5c415) + tlInt32(0))
// messages.sponsoredMessagesEmpty#1839490f
private let tlSponsoredMessagesEmpty = Data(tlInt32(0x1839490f))

/// The local answer to a request the Solvgram menu filters out, nil to send it as usual.
/// `peerId` is the chat a read receipt is for, when the caller knows it: its Ghost Mode exception
/// then decides instead of Ghost Mode itself.
func solvgramFilteredResponse(functionName: String, peerId: Int64? = nil) -> Data? {
    switch functionName {
    case "messages.readHistory":
        return SolvgramSettings.hidesReadReceipts(peerId: peerId) ? tlAffectedMessagesEmpty : nil
    case "channels.readHistory", "messages.readDiscussion", "messages.readSavedHistory", "messages.readEncryptedHistory":
        return SolvgramSettings.hidesReadReceipts(peerId: peerId) ? tlBoolTrue : nil
    case "stories.readStories":
        return SolvgramSettings.hideStoryViews ? tlEmptyVector : nil
    case "stories.incrementStoryViews":
        return SolvgramSettings.hideStoryViews ? tlBoolTrue : nil
    case "messages.getSponsoredMessages":
        return SolvgramSettings.hideAds ? tlSponsoredMessagesEmpty : nil
    case "messages.readMessageContents":
        // A voice or video message listened to (and the like): kept back like a read receipt. Disappearing
        // media that Keep Disappearing Media holds on to is left out by the caller.
        return SolvgramSettings.hidesReadReceipts(peerId: peerId) ? tlAffectedMessagesEmpty : nil
    case "channels.readMessageContents":
        return SolvgramSettings.hidesReadReceipts(peerId: peerId) ? tlBoolTrue : nil
    default:
        return nil
    }
}
