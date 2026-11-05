import Foundation

func require(_ condition: @autoclosure () -> Bool,_ message:String) { precondition(condition(),message) }
let defaults = UserDefaults.standard
let keys = [SolvgramSettings.Key.ghostMode,SolvgramSettings.Key.hideReadReceipts,SolvgramSettings.Key.hideStoryViews,SolvgramSettings.Key.hideAds,SolvgramSettings.Key.ghostExceptions]
let saved = keys.map { defaults.object(forKey:$0) }
defer { for (key,value) in zip(keys,saved) { defaults.set(value,forKey:key) } }
let readMethods = ["messages.readHistory","channels.readHistory","messages.readDiscussion","messages.readSavedHistory","messages.readEncryptedHistory","messages.readMessageContents","channels.readMessageContents"]
defaults.set(true,forKey:SolvgramSettings.Key.hideReadReceipts)
defaults.set(false,forKey:SolvgramSettings.Key.ghostMode)
defaults.removeObject(forKey:SolvgramSettings.Key.ghostExceptions)
for method in readMethods { require(solvgramFilteredResponse(functionName:method,peerId:42) == nil,"An inactive Ghost Mode passes read receipts") }
SolvgramSettings.setGhostException(.hide,peerId:42)
for method in readMethods { require(solvgramFilteredResponse(functionName:method,peerId:42) != nil,"Always On applies even when the global switch is off") }
defaults.set(true,forKey:SolvgramSettings.Key.ghostMode)
SolvgramSettings.setGhostException(.show,peerId:42)
for method in readMethods { require(solvgramFilteredResponse(functionName:method,peerId:42) == nil,"Always Off bypasses the global hiding policy") }
for method in readMethods { require(solvgramFilteredResponse(functionName:method,peerId:43) != nil,"Another chat still follows the global policy") }
defaults.set(false,forKey:SolvgramSettings.Key.hideReadReceipts)
for method in readMethods { require(solvgramFilteredResponse(functionName:method,peerId:43) == nil,"Disabling the read-receipt option is immediate") }
defaults.set(true,forKey:SolvgramSettings.Key.hideStoryViews)
defaults.set(false,forKey:SolvgramSettings.Key.ghostMode)
require(solvgramFilteredResponse(functionName:"stories.readStories")?.count == 8,"Anonymous story views return a valid empty vector independently of Ghost Mode")
require(solvgramFilteredResponse(functionName:"stories.incrementStoryViews") == Data([0xb5,0x75,0x72,0x99]),"Story-view increments return TL boolTrue")
defaults.set(true,forKey:SolvgramSettings.Key.hideAds)
require(solvgramFilteredResponse(functionName:"messages.getSponsoredMessages") == Data([0x0f,0x49,0x39,0x18]),"Hidden ads return the schema's empty sponsored-messages constructor")
require(solvgramFilteredResponse(functionName:"messages.sendMessage") == nil,"Sending is never filtered")
require(solvgramFilteredResponse(functionName:"unknown.method") == nil,"Unknown API methods pass through unchanged")
print("REQUEST_FILTER_AUDIT_OK cases=40")
