import Foundation
import UIKit
import AVFoundation
import UniformTypeIdentifiers
// Only engine storage identities and legacy navigation are isolated. Signal delivery,
// metadata, security scopes, file coordination and file copying use production code.
public protocol EngineRawMediaResource {}
public protocol TelegramMediaResource: EngineRawMediaResource {}
public struct EngineRawMediaResourceId { public init(_ value:String) {} }
public func enginePersistentHash32(_ value:String)->Int32 { 0 }
public final class EnginePostboxDecoder {
 public func decodeStringForKey(_ key:String,orElse:String)->String { orElse }
 public func decodeBoolForKey(_ key:String,orElse:Bool)->Bool { orElse }
}
public final class EnginePostboxEncoder {
 public func encodeString(_ value:String,forKey:String) {}
 public func encodeBool(_ value:Bool,forKey:String) {}
}
public protocol EngineRawMediaResourceDataFetchCopyLocalItem:AnyObject { func copyTo(url:URL)->Bool }
public enum EngineMediaResourceDataFetchError { case generic }
public final class AuditTempFile {
 public let path:String
 init(_ name:String){path=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+name).path}
 deinit {try? FileManager.default.removeItem(atPath:path)}
}
public enum EngineMediaResourceDataFetchResult {case reset;case copyLocalItem(EngineRawMediaResourceDataFetchCopyLocalItem);case moveTempFile(file:AuditTempFile)}
public final class EngineTempBox {
 public static let shared=EngineTempBox()
 public func tempFile(fileName:String)->AuditTempFile { AuditTempFile(fileName) }
}
extension CGSize {
 func fitted(_ other:CGSize)->CGSize {let scale=min(other.width/width,other.height/height);return CGSize(width:width*scale,height:height*scale)}
}
func generateScaledImage(image:UIImage,size:CGSize)->UIImage? {UIGraphicsImageRenderer(size:size).image {_ in image.draw(in:CGRect(origin:.zero,size:size))}}
func generatePdfPreviewImage(url:URL,size:CGSize)->UIImage? { nil } // PDF rasterization is outside this audit.
public typealias ViewController=UIViewController
public final class PresentationTheme {var overallDarkAppearance=false}
public enum LegacyControllerPresentation {case modal(animateIn:Bool)}
public enum AuditStatusStyle {case Black}
public final class AuditStatusBar {var statusBarStyle=AuditStatusStyle.Black}
open class LegacyController:UIViewController {
 var presentationCompleted:(()->Void)?
 var statusBar=AuditStatusBar()
 var dismissCount=0
 init(presentation:LegacyControllerPresentation,theme:PresentationTheme?){super.init(nibName:nil,bundle:nil)}
 required public init?(coder:NSCoder){fatalError()}
 func bind(controller:UIViewController) {}
 func dismiss(completion:(()->Void)?=nil){dismissCount += 1;completion?()}
}
