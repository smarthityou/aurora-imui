//
//  IMUICameraCell.swift
//  IMUIChat
//
//  Created by oshumini on 2017/3/9.
//  Copyright © 2017年 HXHG. All rights reserved.
//

import UIKit
import Photos
import AVFoundation


private enum SessionSetupResult {
		case success
		case notAuthorized
		case configurationFailed
}

private enum LivePhotoMode {
		case on
		case off
}


// TODO: Need to  Restructure
@available(iOS 8.0, *)
class IMUICameraCell: UICollectionViewCell, IMUIFeatureCellProtocal {

  @IBOutlet weak var switchCameraModeBtn: UIButton!
  @IBOutlet weak var cameraShotBtn: UIButton!
  @IBOutlet weak var switchCameraDeviceBtn: UIButton!
  @IBOutlet weak var resizeCameraPreviewBtn: UIButton!
  @IBOutlet weak var cameraPreviewView: IMUICameraPreviewView!
  
  weak var delegate: IMUIInputViewDelegate?
  
  var inputViewDelegate: IMUIInputViewDelegate? {
    set {
      self.delegate = newValue
    }
    
    get {
      return self.delegate
    }
  }
  
  private var _inProgressPhotoCaptureDelegates: Any?
  @available(iOS 10.0, *)
  var inProgressPhotoCaptureDelegates: [Int64 : IMUIPhotoCaptureDelegate] {
    get {
      if _inProgressPhotoCaptureDelegates == nil {
        _inProgressPhotoCaptureDelegates = [Int64 : IMUIPhotoCaptureDelegate]()
      }
      return _inProgressPhotoCaptureDelegates as! [Int64 : IMUIPhotoCaptureDelegate]
    }
    
    set {
      _inProgressPhotoCaptureDelegates = newValue
    }
  }
  
  private var inProgressLivePhotoCapturesCount = 0
  
  private var isPhotoMode: Bool = true {
    didSet {
      self.switchCameraModeBtn.isSelected = !isPhotoMode
      self.cameraShotBtn.isSelected = !isPhotoMode
    }
  }

  private let stillImageOutput = AVCaptureStillImageOutput()
  private let session = AVCaptureSession()
  private var setupResult: SessionSetupResult = .success
  
  var videoFileOutput: AVCaptureMovieFileOutput?
  
  // OutPut
  private var _photoOutput: Any?
  @available(iOS 10.0, *)
  var photoOutput: AVCapturePhotoOutput? {
    get {
      return _photoOutput as? AVCapturePhotoOutput
    }
    
    set {
      _photoOutput = newValue
    }
  }

  var videoDeviceInput: AVCaptureDeviceInput!
  private var livePhotoMode: LivePhotoMode = .off
  var backgroundRecordingID: UIBackgroundTaskIdentifier? = nil

  private var isSessionRunning = false
  private var sessionRunningObserveContext = 0
  private let sessionQueue = DispatchQueue(label: "session queue", attributes: [], target: nil) // Communicate with the session and other session objects on this
  
  override func awakeFromNib() {
    super.awakeFromNib()
    cameraPreviewView.session = session
    
    switch AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo) {
    case .authorized:
      // The user has previously granted access to the camera.
      break
      
    case .notDetermined:
      sessionQueue.suspend()
      AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo, completionHandler: { [unowned self] granted in
        if !granted {
          self.setupResult = .notAuthorized
        }
        self.sessionQueue.resume()
      })
      
    default:
      // The user has previously denied access.
      setupResult = .notAuthorized
    }
    
    sessionQueue.async { [unowned self] in
      self.configureSession()
    }
  }
  
  
  override func layoutSubviews() {
    super.layoutSubviews()
    sessionQueue.async {
      switch self.setupResult {
      case .success:
        self.session.startRunning()
        self.isSessionRunning = self.session.isRunning
        
      case .notAuthorized:
        DispatchQueue.main.async { [unowned self] in
          print("AVCam doesn't have permission to use the camera, please change privacy settings")
        }
        
      case .configurationFailed:
        DispatchQueue.main.async { [unowned self] in
          print("Unable to capture media")
        }
      }
    }
  }
  
  // -MARK: Click Event
  @IBAction func clickCameraSwitch(_ sender: Any) {
    if isPhotoMode {
      if #available(iOS 10.0, *) {
        self.capturePhotoAfter_iOS10()
      } else {
        self.capturePhotoBefore_iOS8()
      }
    } else {

      if !(videoFileOutput!.isRecording) {
        
        let outputPath = self.getPath()
        let fileManager = FileManager()
        if fileManager.fileExists(atPath: outputPath) {
          do {
            try fileManager.removeItem(at: URL(fileURLWithPath: outputPath))
          } catch {
            print("removefile fail")
          }
          
        }
        session.beginConfiguration()
        session.sessionPreset = AVCaptureSessionPreset352x288
        session.commitConfiguration()
        videoFileOutput?.startRecording(toOutputFileURL: URL(fileURLWithPath: outputPath), recordingDelegate: self)
      } else {
        videoFileOutput?.stopRecording()
      }
    }

  }
  
  @IBAction func clickToSwitchCamera(_ sender: Any) {
    
  }
  
  @IBAction func clickToChangeCameraMode(_ sender: Any) {
    isPhotoMode = !isPhotoMode
    if isPhotoMode {
      session.sessionPreset = AVCaptureSessionPresetPhoto
    } else {
      session.sessionPreset = AVCaptureSessionPreset352x288
    }
  }
  
  @IBAction func clickToAdjustCameraViewSize(_ sender: Any) {
    
  }
  
  @available(iOS 10.0, *)
  func capturePhotoAfter_iOS10() {
    let videoPreviewLayerOrientation = cameraPreviewView.videoPreviewLayer.connection.videoOrientation
    
    sessionQueue.async {
      if let photoOutputConnection = self.photoOutput?.connection(withMediaType: AVMediaTypeVideo) {
        photoOutputConnection.videoOrientation = videoPreviewLayerOrientation
      }
      
      let photoSettings = AVCapturePhotoSettings()
      photoSettings.flashMode = .auto
      
      photoSettings.isHighResolutionPhotoEnabled = false
      
      if photoSettings.availablePreviewPhotoPixelFormatTypes.count > 0 {
        photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String : photoSettings.availablePreviewPhotoPixelFormatTypes.first!]
      }
      if self.livePhotoMode == .on && (self.photoOutput?.isLivePhotoCaptureSupported)! { // Live Photo capture is not supported in movie mode.
        let livePhotoMovieFileName = NSUUID().uuidString
        let livePhotoMovieFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((livePhotoMovieFileName as NSString).appendingPathExtension("mov")!)
        photoSettings.livePhotoMovieFileURL = URL(fileURLWithPath: livePhotoMovieFilePath)
      }
      
      let photoCaptureDelegate = IMUIPhotoCaptureDelegate(with: photoSettings, willCapturePhotoAnimation: {
        DispatchQueue.main.async { [unowned self] in
          self.cameraPreviewView.videoPreviewLayer.opacity = 0
          UIView.animate(withDuration: 0.25) { [unowned self] in
            self.cameraPreviewView.videoPreviewLayer.opacity = 1
          }
        }
      }, capturingLivePhoto: { capturing in
        self.sessionQueue.async { [unowned self] in
          if capturing {
            self.inProgressLivePhotoCapturesCount += 1
          }
          else {
            self.inProgressLivePhotoCapturesCount -= 1
          }
          
          let inProgressLivePhotoCapturesCount = self.inProgressLivePhotoCapturesCount
          DispatchQueue.main.async { [unowned self] in
            if inProgressLivePhotoCapturesCount > 0 {
//              self.capturingLivePhotoLabel.isHidden = false
            }
            else if inProgressLivePhotoCapturesCount == 0 {
//              self.capturingLivePhotoLabel.isHidden = true
            }
            else {
              print("Error: In progress live photo capture count is less than 0");
            }
          }
        }
      }, completed: { [unowned self] photoCaptureDelegate in
        self.inputViewDelegate?.finishShootPicture(picture: photoCaptureDelegate.photoData!)
        self.sessionQueue.async { [unowned self] in
          self.inProgressPhotoCaptureDelegates[photoCaptureDelegate.requestedPhotoSettings.uniqueID] = nil
        }
        }
      )
      
      self.inProgressPhotoCaptureDelegates[photoCaptureDelegate.requestedPhotoSettings.uniqueID] = photoCaptureDelegate
      self.photoOutput?.capturePhoto(with: photoSettings, delegate: photoCaptureDelegate)
    }
  }
  
  private func capturePhotoBefore_iOS8() {

    stillImageOutput.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
    
    var videoConnection: AVCaptureConnection? = nil
    for connection in stillImageOutput.connections as! [AVCaptureConnection] {
      for port in connection.inputPorts as! [AVCaptureInputPort]{
        if port.mediaType == AVMediaTypeVideo {
          videoConnection = connection
          break
        }
      }
      
      if videoConnection != nil { break }
    }
    
    print("about to request a capture from: \(stillImageOutput)")
    stillImageOutput.captureStillImageAsynchronously(from: videoConnection) { (imageSampleBuffer, error) in
      var exifAttachments = CMGetAttachment(imageSampleBuffer!, kCGImagePropertyExifDictionary, nil)
      
      if (exifAttachments != nil) {
        print("exifAttachments exit")
      } else {
        print("exifAttachments not exit")
      }
      
      let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageSampleBuffer)
      self.inputViewDelegate?.finishShootPicture(picture: imageData!)
      let image = UIImage(data: imageData!)
      UIImageWriteToSavedPhotosAlbum(image!, nil, nil, nil)
      
    }
  }
  
  private func configureSession() {
    
    if setupResult != .success {
      return
    }
    
    session.beginConfiguration()
    session.sessionPreset = AVCaptureSessionPresetPhoto
    
    do {
      var defaultVideoDevice: AVCaptureDevice?
      
      if #available(iOS 10.0, *) {
        if let dualCameraDevice = AVCaptureDevice.defaultDevice(withDeviceType: .builtInDuoCamera, mediaType: AVMediaTypeVideo, position: .back) {
          defaultVideoDevice = dualCameraDevice
        }
        else if let backCameraDevice = AVCaptureDevice.defaultDevice(withDeviceType: .builtInWideAngleCamera, mediaType: AVMediaTypeVideo, position: .back) {
          defaultVideoDevice = backCameraDevice
        }
        else if let frontCameraDevice = AVCaptureDevice.defaultDevice(withDeviceType: .builtInWideAngleCamera, mediaType: AVMediaTypeVideo, position: .front) {
          
          defaultVideoDevice = frontCameraDevice
        }
      } else {
        defaultVideoDevice = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
      }
      
      let videoDeviceInput = try AVCaptureDeviceInput(device: defaultVideoDevice)
      
      if session.canAddInput(videoDeviceInput) {
        session.addInput(videoDeviceInput)
        self.videoDeviceInput = videoDeviceInput
        
        DispatchQueue.main.async {
          
          let statusBarOrientation = UIApplication.shared.statusBarOrientation
          var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
          if statusBarOrientation != .unknown {
            if let videoOrientation = statusBarOrientation.videoOrientation {
              initialVideoOrientation = videoOrientation
            }
          }
          
          self.cameraPreviewView.videoPreviewLayer.connection.videoOrientation = initialVideoOrientation
        }
      } else {
        print("Could not add video device input to the session")
        setupResult = .configurationFailed
        session.commitConfiguration()
        return
      }
    } catch {
      print("Could not create video device input: \(error)")
      setupResult = .configurationFailed
      session.commitConfiguration()
      return
    }

    do {
      let audioDevice = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeAudio)
      let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
      
      if session.canAddInput(audioDeviceInput) {
        session.addInput(audioDeviceInput)
      } else {
        print("Could not add audio device input to the session")
      }
    } catch {
      print("Could not create audio device input: \(error)")
    }
    
    // configure output
    
    if #available(iOS 10.0, *) {
      self.photoOutput = AVCapturePhotoOutput()
      
      if session.canAddOutput(self.photoOutput!) {
        session.addOutput(self.photoOutput)
        self.photoOutput?.isHighResolutionCaptureEnabled = true
        self.photoOutput?.isLivePhotoCaptureEnabled = (self.photoOutput?.isLivePhotoCaptureSupported)!
        livePhotoMode = (photoOutput?.isLivePhotoCaptureSupported)! ? .on : .off
      } else {
        print("Could not add photo output to the session")
        setupResult = .configurationFailed
        session.commitConfiguration()
        return
      }
    } else {
      if session.canAddOutput(stillImageOutput) {
        session.addOutput(stillImageOutput)
      }
    }
    
    videoFileOutput = AVCaptureMovieFileOutput()
    if session.canAddOutput(videoFileOutput) {
      session.addOutput(videoFileOutput)
      let maxDuration = CMTime(seconds: 20, preferredTimescale: 1)
      videoFileOutput?.maxRecordedDuration = maxDuration
      videoFileOutput?.minFreeDiskSpaceLimit = 1000
    }
    
    session.commitConfiguration()
  }

  
  func getPath() -> String {
    var recorderPath:String? = nil
    let now:Date = Date()
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yy-MMMM-dd"
//    recorderPath = "\(NSHomeDirectory())/Documents/"
    recorderPath = NSTemporaryDirectory()
    dateFormatter.dateFormat = "yyyy-MM-dd-hh-mm-ss"
    recorderPath?.append("\(dateFormatter.string(from: now))-video.mp4")
    return recorderPath!
  }
}

extension UIInterfaceOrientation {
  var videoOrientation: AVCaptureVideoOrientation? {
    switch self {
    case .portrait: return .portrait
    case .portraitUpsideDown: return .portraitUpsideDown
    case .landscapeLeft: return .landscapeLeft
    case .landscapeRight: return .landscapeRight
    default: return nil
    }
  }
}


extension IMUICameraCell: AVCaptureFileOutputRecordingDelegate {
  func capture(_ captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAt outputFileURL: URL!, fromConnections connections: [Any]!, error: Error!) {
    if error == nil {
      
      self.inputViewDelegate?.finishShootVideo(videoPath: outputFileURL.path, durationTime: captureOutput.recordedDuration.seconds)
    } else {
      print("record video fail")
    }
    
  }
  
  func capture(_ captureOutput: AVCaptureFileOutput!, didStartRecordingToOutputFileAt fileURL: URL!, fromConnections connections: [Any]!) {

  }
}