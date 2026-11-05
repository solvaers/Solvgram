import Foundation

@main
struct ArchiveAudit {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data(("ARCHIVE_AUDIT_FAILED: " + message + "\n").utf8))
            exit(1)
        }
    }

    static func main() throws {
        let args = CommandLine.arguments
        let suite = args.count > 2 ? args[2] : "app.solvgram.audit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        if args.count > 1, args[1] == "read" {
            let store = SolvgramArchiveStorage(defaults: defaults)
            check(store.previousTexts("account-A:message") == ["original", "edited"], "A new process restores the archive")
            check(store.previousTexts("account-B:message") == ["different account"], "Accounts remain isolated after restart")
            check(store.storiesViewedAnonymously("account-A:story"), "Anonymous story provenance survives restarting the process")
            check(!store.storiesViewedAnonymously("account-B:story"), "Restarted story provenance stays account scoped")
            defaults.removePersistentDomain(forName: suite)
            print("ARCHIVE_PROCESS_RESTART_OK")
            return
        }
        defaults.removePersistentDomain(forName: suite)
        if args.count > 1, args[1] == "write" {
            let store = SolvgramArchiveStorage(defaults: defaults)
            store.recordEdit("account-A:message", previousText: "original")
            store.recordEdit("account-A:message", previousText: "edited")
            store.recordEdit("account-B:message", previousText: "different account")
            store.setStoriesViewedAnonymously("account-A:story", maxId:12, anonymously:true)
            store.flush()
            defaults.synchronize() // Test process boundary, not production polling.
            print("ARCHIVE_PROCESS_WRITE_OK")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SolvgramArchiveStorage(defaults: defaults)
        let started = Date()
        DispatchQueue.concurrentPerform(iterations: 400) { i in
            let key = "account-A:\(i)"
            store.recordEdit(key, previousText: "text \(i)")
            store.markDeleted([key])
            store.markDisappearing(key)
            store.setStoriesViewedAnonymously(key, maxId:Int32(i + 1), anonymously:true)
        }
        store.flush()
        let restored = SolvgramArchiveStorage(defaults: defaults)
        for i in 0..<400 {
            let key = "account-A:\(i)"
            check(restored.previousTexts(key) == ["text \(i)"], "Concurrent edits are never lost")
            check(restored.isDeleted(key), "Concurrent deletion marks persist")
            check(restored.isDisappearing(key), "Concurrent disappearing-media marks persist")
            check(restored.storiesViewedAnonymously(key), "Concurrent story marks persist")
            check(!restored.isDeleted("account-B:\(i)"), "New metadata never crosses accounts")
        }
        for i in 0..<80 { store.recordEdit("versions", previousText:"version \(i)") }
        check(store.previousTexts("versions").count == 50, "A message has at most 50 archived versions")
        check(store.previousTexts("versions").first == "version 0", "The original text is retained")
        check(store.previousTexts("versions").last == "version 79", "The latest previous version is retained")
        for _ in 0..<100 { store.recordEdit("versions", previousText:"version 79") }
        check(store.previousTexts("versions").count == 50, "Identical refetches do not duplicate history")
        store.markDeleted((0..<20_010).map { "bounded:\($0)" })
        check(!store.isDeleted("bounded:0") && store.isDeleted("bounded:20009"), "Deletion metadata is bounded and keeps recent entries")
        store.setStoriesViewedAnonymously("account-A:newer-story", maxId:12, anonymously:true)
        store.setStoriesViewedAnonymously("account-A:newer-story", maxId:10, anonymously:false)
        check(store.storiesViewedAnonymously("account-A:newer-story"), "An older ordinary view preserves newer anonymous provenance")
        check(!store.storiesViewedAnonymously("account-B:newer-story"), "Anonymous provenance never crosses accounts")
        store.setStoriesViewedAnonymously("account-A:newer-story", maxId:12, anonymously:false)
        check(!store.storiesViewedAnonymously("account-A:newer-story"), "A matching ordinary view clears anonymous provenance")
        store.unmarkDisappearing("account-A:1")
        store.setStoriesViewedAnonymously("account-A:1", maxId:2, anonymously:false)
        store.flush()
        let reloaded = SolvgramArchiveStorage(defaults: defaults)
        check(!reloaded.isDisappearing("account-A:1"), "Explicit media removal persists")
        check(!reloaded.storiesViewedAnonymously("account-A:1"), "Confirmed story views clear the anonymous mark")

        store.mergePreviousTexts("server:forward", texts:["a","b"])
        store.mergePreviousTexts("server:forward", texts:["b","c"])
        check(store.previousTexts("server:forward") == ["a","b","c"], "Overlapping newer server histories merge once")
        store.mergePreviousTexts("server:forward", texts:["b","c"])
        check(store.previousTexts("server:forward") == ["a","b","c"], "Replayed server histories are idempotent")
        store.mergePreviousTexts("server:backward", texts:["b","c"])
        store.mergePreviousTexts("server:backward", texts:["a","b"])
        check(store.previousTexts("server:backward") == ["a","b","c"], "Earlier server versions are prepended in chronological order")
        store.mergePreviousTexts("server:empty-caption", texts:["","caption"])
        check(store.previousTexts("server:empty-caption") == ["","caption"], "A former empty media caption is preserved")
        store.mergePreviousTexts("server:bounded", texts:(0..<70).map { String($0) })
        let serverTexts = store.previousTexts("server:bounded")
        check(serverTexts.count == 50 && serverTexts.first == "0" && serverTexts.last == "69", "Server history respects original-text retention and the version bound")

        // Budget/ordering checks use an independent archive, so retaining the
        // original text of an edited message is checked separately from eviction.
        let boundedSuite = suite + ".budget"
        let boundedDefaults = UserDefaults(suiteName:boundedSuite)!
        defer { boundedDefaults.removePersistentDomain(forName:boundedSuite) }
        let bounded = SolvgramArchiveStorage(defaults:boundedDefaults)
        for i in 0..<5_010 { bounded.recordEdit("id-\(i)",previousText:"value \(i)") }
        bounded.flush()
        check(bounded.previousTexts("id-0").isEmpty && bounded.previousTexts("id-5009") == ["value 5009"], "The message-count limit evicts the oldest history")
        let orderBefore = boundedDefaults.stringArray(forKey:"SolvgramEditHistoryOrder")!
        let reinitialized = SolvgramArchiveStorage(defaults:boundedDefaults)
        reinitialized.recordEdit("new-after-restart",previousText:"new")
        reinitialized.flush()
        let orderAfter = boundedDefaults.stringArray(forKey:"SolvgramEditHistoryOrder")!
        check(Array(orderBefore.dropFirst()) == Array(orderAfter.dropLast()), "Eviction order survives restarting the archive")
        for i in 0..<190 { reinitialized.recordEdit("large-\(i)",previousText:String(repeating:"a",count:100_000)) }
        reinitialized.flush()
        let history = boundedDefaults.dictionary(forKey:SolvgramSettings.Key.editHistory) as! [String:[String]]
        let bytes = history.values.reduce(0) { $0 + $1.reduce(0) { $0 + $1.utf8.count } }
        check(bytes <= 16 * 1024 * 1024, "Total text history has a 16 MiB budget")
        check(history["large-189"] != nil, "The newest history survives byte-budget eviction")

        let legacySuite = suite + ".legacy"
        let legacy = UserDefaults(suiteName:legacySuite)!
        defer { legacy.removePersistentDomain(forName:legacySuite) }
        legacy.set(["old-id":["old text"]],forKey:SolvgramSettings.Key.editHistory)
        let migrated = SolvgramArchiveStorage(defaults:legacy)
        check(migrated.previousTexts("account:old-id",legacyKey:"old-id") == ["old text"], "Old unscoped records remain readable")
        migrated.recordEdit("account:old-id",previousText:"current text",legacyKey:"old-id")
        migrated.flush()
        check(migrated.previousTexts("account:old-id") == ["old text","current text"], "Existing history is preserved on the first scoped edit")
        check(migrated.previousTexts("another-account:old-id",legacyKey:"old-id") == ["old text"], "New edits are not added to the legacy fallback")

        let settings = UserDefaults.standard
        let newKeys = [SolvgramSettings.Key.voiceSpeed,SolvgramSettings.Key.allowProtectedContent,SolvgramSettings.Key.allowScreenshots,"SolvgramVoiceSpeed","SolvgramVoiceTempo"]
        let savedNew = newKeys.map { settings.object(forKey:$0) }
        defer { for (key,value) in zip(newKeys,savedNew) { settings.set(value,forKey:key) } }
        settings.removeObject(forKey:newKeys[4])
        settings.set(2,forKey:newKeys[3])
        settings.removeObject(forKey:newKeys[0])
        check(SolvgramSettings.voiceSpeed == 0.75,"Displayed 1x defaults to the revised 0.75 baseline")
        settings.set(4,forKey:newKeys[3]);settings.removeObject(forKey:newKeys[0])
        check(abs(SolvgramSettings.voiceSpeed - 1.05) < 0.0001,"An old custom tempo migrates to the nearest revised preset")
        check(settings.integer(forKey:newKeys[0]) == 5,"Migrated tempo is saved under the new key")
        settings.set(99,forKey:newKeys[0]);check(abs(SolvgramSettings.voiceSpeed - 1.05) < 0.0001,"Invalid high speed is clamped")
        settings.set(-5,forKey:newKeys[0]);check(abs(SolvgramSettings.voiceSpeed - 0.45) < 0.0001,"Invalid low speed is clamped")
        settings.set(4,forKey:newKeys[4]);settings.removeObject(forKey:newKeys[0])
        check(abs(SolvgramSettings.voiceSpeed - 0.9) < 0.0001,"Quarter-step custom speed migrates to the nearest 0.2 step")
        check(settings.integer(forKey:newKeys[0]) == 4,"Quarter-step migration is persisted")
        for saving in [false,true] { for screenshots in [false,true] {
            settings.set(saving,forKey:newKeys[1]);settings.set(screenshots,forKey:newKeys[2])
            check(!SolvgramSettings.storyCaptureProtected(false),"Public stories are never capture protected")
            check(SolvgramSettings.storyCaptureProtected(true) == (!saving && !screenshots),"Story capture honors both saving and screenshot options")
        } }

        let keys = [SolvgramSettings.Key.fakeLocation,SolvgramSettings.Key.fakeLatitude,SolvgramSettings.Key.fakeLongitude]
        let previous = keys.map { settings.object(forKey:$0) }
        defer { for (key,value) in zip(keys,previous) { settings.set(value,forKey:key) } }
        settings.set(true,forKey:keys[0]); settings.set(55.75,forKey:keys[1]); settings.removeObject(forKey:keys[2])
        check(SolvgramSettings.fakeLocation == nil, "A missing longitude is not silently replaced by zero")
        settings.set(37.61,forKey:keys[2])
        check(SolvgramSettings.fakeLocation?.latitude == 55.75, "A valid saved coordinate remains supported")
        settings.set(91.0,forKey:keys[1]); check(SolvgramSettings.fakeLocation == nil,"Invalid latitude is rejected")
        settings.set(Double.nan,forKey:keys[1]); check(SolvgramSettings.fakeLocation == nil,"Nonfinite coordinates are rejected")
        store.setEditHistoryLimit(10)
        check(store.editHistoryLimit == 10, "Version limit is configurable")
        let limited = store.previousTexts("versions")
        check(limited.count == 10 && limited.first == "version 0" && limited.last == "version 79", "Lowering the version limit preserves the original and newest versions")
        store.setEditHistoryLimit(100)
        for i in 80..<180 { store.recordEdit("versions", previousText: "version \(i)") }
        check(store.previousTexts("versions").count == 100, "Raised limit applies to new history")
        store.removeEditHistory(["versions"])
        check(store.previousTexts("versions").isEmpty, "Edit-only cleanup removes every saved version")
        check(store.isDeleted("bounded:20009"), "Edit-only cleanup preserves deletion marks")
        store.mergePreviousTexts("server:moving-window", texts: (0..<50).map(String.init))
        store.mergePreviousTexts("server:moving-window", texts: ["0"] + (2...50).map(String.init))
        check(store.previousTexts("server:moving-window") == (0...50).map(String.init), "Moving server windows preserve the newest version without duplicating the original")
        store.mergePreviousTexts("server:contained", texts: ["b", "c"])
        store.mergePreviousTexts("server:contained", texts: ["a", "b", "c", "d"])
        check(store.previousTexts("server:contained") == ["a", "b", "c", "d"], "A larger server history does not duplicate the local subsequence")
        print("ARCHIVE_AUDIT_OK concurrent=400 versions=50 maxBytes=\(bytes) elapsed=\(Date().timeIntervalSince(started))")
    }
}
