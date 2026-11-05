@main final class FilePickerAuditApp:UIResponder,UIApplicationDelegate {
 var window:UIWindow?
 private var failures:[String]=[]
 private var checks=0
 var profileMetrics:[String:String]=[:]
 func verify(_ value:Bool,_ name:String){checks += 1;if !value {failures.append(name)}}
 func application(_ app:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool {
  let window=UIWindow(frame:UIScreen.main.bounds);window.rootViewController=UIViewController();window.makeKeyAndVisible();self.window=window
  Task {await self.run()};return true
 }
 func pause(_ duration:Double=0.2) async {try? await Task.sleep(nanoseconds:UInt64(duration*1_000_000_000))}
 func describe(_ url:URL) async -> ICloudFileDescription? {
  await withCheckedContinuation { continuation in
   let disposable=MetaDisposable()
   disposable.set(iCloudFileDescription(url).start(next:{ value in continuation.resume(returning:value);disposable.dispose() }))
  }
 }
 func fetch(_ resource:ICloudFileResource) async -> [EngineMediaResourceDataFetchResult] {
  await withCheckedContinuation {continuation in
   let disposable=MetaDisposable();var results:[EngineMediaResourceDataFetchResult]=[]
   disposable.set(fetchICloudFileResource(resource:resource).start(next:{results.append($0)},completed:{continuation.resume(returning:results);disposable.dispose()}))
  }
 }
 @MainActor func run() async {
  let directory=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
  for name in ["document.txt","literal%document.txt","literal%20space.txt","документ с пробелами.txt","empty.txt"] {
   let url=directory.appendingPathComponent(name);let data=name=="empty.txt" ? Data():Data(("Synthetic payload: "+name).utf8)
   try! data.write(to:url)
   let description=await describe(url)
   verify(description != nil,"Description exists: "+name)
   verify(description?.fileName==name,"Filename roundtrip: "+name)
   verify(description?.fileSize==data.count,"Size roundtrip: "+name)
   if let description {
    var stale=false
    let restored=try? URL(resolvingBookmarkData:Data(base64Encoded:description.urlData)!,bookmarkDataIsStale:&stale)
    verify(restored?.lastPathComponent==name,"Bookmark roundtrip: "+name)
    let results=await fetch(ICloudFileResource(urlData:description.urlData,thumbnail:false))
    var copied=false
    for result in results {if case let .copyLocalItem(item)=result {
     let output=directory.appendingPathComponent(UUID().uuidString)
     copied=item.copyTo(url:output) && (try? Data(contentsOf:output))==data
     try? FileManager.default.removeItem(at:output)
    }}
    verify(copied,"Byte-for-byte upload copy: "+name)
   }
  }
  verify(await describe(directory.appendingPathComponent("missing.txt"))==nil,"Missing file terminates with no description")
  verify(await describe(directory)==nil,"Directory cannot be sent as a regular document")
  verify(await describe(URL(string:"https://example.invalid/document.txt")!)==nil,"Remote URL is rejected")
  var delivered=false;let cancelled=iCloudFileDescription(directory.appendingPathComponent("document.txt")).start(next:{_ in delivered=true});cancelled.dispose();await pause()
  verify(!delivered,"Cancelled metadata is not delivered")
  let image=UIGraphicsImageRenderer(size:CGSize(width:16,height:16)).image {ctx in UIColor.red.setFill();ctx.fill(CGRect(x:0,y:0,width:16,height:16))}
  let imageURL=directory.appendingPathComponent("image.png");try! image.pngData()!.write(to:imageURL)
  if let description=await describe(imageURL) {
   let results=await fetch(ICloudFileResource(urlData:description.urlData,thumbnail:true));var thumbnail=false
   for result in results {if case let .moveTempFile(file)=result {thumbnail=UIImage(contentsOfFile:file.path) != nil}}
   verify(thumbnail,"Coordinated image thumbnail is readable")
  } else {verify(false,"Image description exists")}
  auditProfileNames()
  await pickerLifecycle(directory.appendingPathComponent("document.txt"))
  let report:[String:Any]=["build":"100029","completed":true,"checks":checks,"profileMetrics":profileMetrics,"failures":failures,"boundary":"production picker and file-resource source; real UIKit/Foundation/signals; synthetic app files, no account"]
  try! JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("audit.json"))
 }
 @MainActor func pickerLifecycle(_ url:URL) async {
  let theme=PresentationTheme();var picked:[[URL]]=[]
  let legacy=legacyICloudFilePicker(theme:theme,hasMultiselection:true,completion:{picked.append($0)}) as! LegacyICloudFileController
  window?.rootViewController=legacy;await pause()
  legacy.presentationCompleted?();await pause(0.8)
  guard let picker=legacy.retainedPicker else {verify(false,"Native picker is presented");return}
  verify(picker.delegate === legacy && picker.retainedDelegate === legacy,"Native picker retains its result delegate until completion")
  verify(picker.allowsMultipleSelection,"Multiselect survives native setup")
  picker.viewDidDisappear(false)
  verify(legacy.dismissCount==0 && picked.isEmpty,"Disappearance never cancels or consumes selection")
  legacy.documentPicker(picker,didPickDocumentsAt:[url])
  legacy.documentPicker(picker,didPickDocumentAt:url)
  verify(picked==[[url]] && legacy.dismissCount==1,"Picked files are delivered once after disappearance")
  verify(picker.delegate==nil && picker.retainedDelegate==nil && legacy.retainedPicker==nil,"Picker releases its delegate after delivery")
  legacy.dismiss(animated:false);await pause()
  var cancelled:[[URL]]=[]
  let wrapper=LegacyICloudFileController(presentation:.modal(animateIn:false),theme:theme,completion:{cancelled.append($0)})
  let cancelPicker=DocumentPickerViewController(forOpeningContentTypes:[.item],asCopy:true)
  cancelPicker.delegate=wrapper;cancelPicker.retainedDelegate=wrapper
  wrapper.presentationControllerDidDismiss(UIPresentationController(presentedViewController:cancelPicker,presenting:wrapper))
  wrapper.documentPickerWasCancelled(cancelPicker)
  verify(cancelled.count==1 && cancelled[0].isEmpty,"Interactive cancellation completes once")
  verify(cancelPicker.retainedDelegate==nil,"Cancellation releases delegate")
  verify(!LegacyICloudFilePickerMode.default.asCopy && LegacyICloudFilePickerMode.import.asCopy && LegacyICloudFilePickerMode.export.asCopy,"Existing open/import/export semantics preserved")
 }
}
