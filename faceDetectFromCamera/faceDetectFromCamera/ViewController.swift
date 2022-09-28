//
//  ViewController.swift
//  faceDetectFromCamera
//
//  Created by shun on 2022/09/13.
//  camera2と組み合わせた

import UIKit
import Vision
import AVFoundation
import PhotosUI

class ViewController: UIViewController,AVCaptureVideoDataOutputSampleBufferDelegate {

    @IBOutlet weak var sliderParsonNum: UISlider!
    @IBOutlet weak var buttonTakePhoto: UIButton!
    @IBOutlet weak var buttonChangeCamera: UIButton!
    @IBOutlet weak var buttonShowCameraRoll: UIButton!
    
    @IBOutlet weak var labelParsonNum: UILabel!
    @IBOutlet weak var segmentedControlShutter: UISegmentedControl!
    @IBOutlet weak var stepperParsonNum: UIStepper!
    private var _captureSession = AVCaptureSession()
    private var _videoDevice = AVCaptureDevice.default(for: AVMediaType.video)
    private var _videoOutput = AVCaptureVideoDataOutput()
    private var _videoLayer : AVCaptureVideoPreviewLayer? = nil
    
    private var takePhoto:Bool = false
    // キャプチャーの出力データを受け付けるオブジェクト
    private var photoOutput : AVCapturePhotoOutput?
    
    private var rectArray:[UIView] = []
    var image : UIImage!
    
    private var shutterSpeed :Int = 10
    
    private var photoTakeCount:Int = 0
    
    //撮影ボタンの中心座標
    private var buttonX: Int = 0;
    private var buttonY: Int = 0;

    
    //カメラロール表示用
    private lazy var picker: PHPickerViewController = {
            var configuration = PHPickerConfiguration(photoLibrary: PHPhotoLibrary.shared())
            configuration.filter = .images //画像だけ選択可能
            configuration.selectionLimit = 1 //選択上限をなくす場合は０
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self//delegateを指定
            return picker
        }()
    
    
    func setupVideo( camPos:AVCaptureDevice.Position, orientaiton:AVCaptureVideoOrientation ){
        self._videoLayer = nil
        
        // カメラ関連の設定
        self._captureSession = AVCaptureSession()
        self._videoOutput = AVCaptureVideoDataOutput()
        self._videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: camPos)
            
        // Inputを作ってSessionに追加
        do {
            let videoInput = try AVCaptureDeviceInput(device: self._videoDevice!) as AVCaptureDeviceInput
            self._captureSession.addInput(videoInput)
        } catch let error as NSError {
                print(error)
            }
            // Outputを作ってSessionに追加
        self._videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as AnyHashable as! String : Int(kCVPixelFormatType_32BGRA)]
        self._videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.main)
        self._videoOutput.alwaysDiscardsLateVideoFrames = true
        self._captureSession.addOutput(self._videoOutput)
                
        // 出力データを受け取るオブジェクトの作成
        self.photoOutput = AVCapturePhotoOutput()
        // 出力ファイルのフォーマットを指定
        self.photoOutput!.setPreparedPhotoSettingsArray([AVCapturePhotoSettings(format: [AVVideoCodecKey : AVVideoCodecType.jpeg])], completionHandler: nil)
        _captureSession.addOutput(photoOutput!)
        
        for connection in self._videoOutput.connections {
            connection.videoOrientation = orientaiton
        }
            
        // 出力レイヤを作る
        self._videoLayer = AVCaptureVideoPreviewLayer(session: self._captureSession)
        self._videoLayer?.frame = UIScreen.main.bounds
        self._videoLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
        self._videoLayer?.connection?.videoOrientation = orientaiton
        
        //プレビュー画面を下層のレイヤに表示、多分これでボタンとかが見える
        self.view.layer.insertSublayer(self._videoLayer!, at: 0)
        //self.view.layer.addSublayer(self._videoLayer!)//もとのやつ
            
        // 録画開始
        self._captureSession.startRunning()
    }
    
    private func imageFromSampleBuffer(sampleBuffer: CMSampleBuffer) -> UIImage {
            let imageBuffer: CVImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
            CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = (CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
            let context = CGContext(data: CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0), width: CVPixelBufferGetWidth(imageBuffer), height: CVPixelBufferGetHeight(imageBuffer), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(imageBuffer), space: colorSpace, bitmapInfo: bitmapInfo)
            let imageRef = context!.makeImage()
            
            CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
            let resultImage: UIImage = UIImage(cgImage: imageRef!)
            return resultImage
    }
    
    func drawRect(box:CGRect, color:UIColor){
            let xRate : CGFloat = self.view.bounds.width / self.image.size.width
            let yRate : CGFloat = self.view.bounds.height / self.image.size.height
            
            let faceRect = CGRect(
                //フロントカメラ
//                x: (1 - box.maxX) * self.image.size.width * xRate,
//                y: (1 - box.maxY) * self.image.size.height * yRate,
//                width: box.width * self.image.size.width * xRate,
//                height: box.height * self.image.size.height * yRate
                
                //背面カメラ
                x: box.minX * self.image.size.width * xRate,
                y: (1 - box.maxY) * self.image.size.height * yRate,
                width: box.width * self.image.size.width * xRate,
                height: box.height * self.image.size.height * yRate

            )
            
            let faceTrackingView = UIView(frame: faceRect)
            faceTrackingView.backgroundColor = UIColor.clear
            faceTrackingView.layer.borderWidth = 5.0
            //faceTrackingView.layer.borderColor = UIColor.green.cgColor
            faceTrackingView.layer.borderColor = color.cgColor
            self.view.addSubview(faceTrackingView)
            self.view.bringSubviewToFront(faceTrackingView)
            rectArray.append(faceTrackingView)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            
            DispatchQueue.main.async {
                self.image = self.imageFromSampleBuffer(sampleBuffer: sampleBuffer)
                // 顔検出用のリクエストを生成
                let request = VNDetectFaceRectanglesRequest { (request: VNRequest, error: Error?) in
                    
                    self.rectArray.forEach{ $0.removeFromSuperview() }
                    self.rectArray.removeAll()
                    
                    var parsonCount:Int = 0
                    for observation in request.results as! [VNFaceObservation] {
                        //print(observation.roll)
                        //print(observation.yaw)
                        let yaw = observation.yaw?.doubleValue
                        print(fabs(yaw!))
                        
                        //self.drawRect(box: observation.boundingBox, color: UIColor.red)
                        // 枠線を描画する
                        if fabs(yaw!) > 0.5 {//顔の向きが横向き
                            self.drawRect(box: observation.boundingBox, color: UIColor.red)
                        } else {//顔が正面を向いている
                            self.drawRect(box: observation.boundingBox, color: UIColor.magenta)
                            //正面を向いている人数をカウント
                            parsonCount += 1
                        }
                    }
                    
                    if self.takePhoto == true {//撮影ボタンが押されているか
                        if parsonCount == Int(self.stepperParsonNum.value) {//画面と設定人数が一致
                            if self.photoTakeCount % self.shutterSpeed == 0{
                                //写真へ保存
                                let settings = AVCapturePhotoSettings()
                                // フラッシュの設定
                                settings.flashMode = .off
                                // カメラの手ぶれ補正
                                settings.isAutoStillImageStabilizationEnabled = true
                                // 撮影された画像をdelegateメソッドで処理
                                self.photoOutput?.capturePhoto(with: settings, delegate: self as! AVCapturePhotoCaptureDelegate)
                            }
                            self.photoTakeCount += 1
                            if self.photoTakeCount == 120{
                                self.photoTakeCount = 1
                            }
                        }
                    }
                    
                }
                
                // 顔検出開始
                if let cgImage = self.image.cgImage {
                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    try? handler.perform([request])
                }
            }
    }
    
    // ボタンのスタイルを設定
    func styleCaptureButton() {
//        buttonTakePhoto.layer.borderColor = UIColor.white.cgColor
//        buttonTakePhoto.layer.borderWidth = 5
//        buttonTakePhoto.clipsToBounds = true
//        buttonTakePhoto.layer.cornerRadius = min(buttonTakePhoto.frame.width, buttonTakePhoto.frame.height) / 2
        
        buttonX = Int(buttonTakePhoto.frame.minX + buttonTakePhoto.frame.width / 2)
        buttonY = Int(buttonTakePhoto.frame.minY + buttonTakePhoto.frame.height / 2)
        //背景色
        buttonTakePhoto.backgroundColor = UIColor.red
        //枠線を追加
        buttonTakePhoto.layer.borderColor = UIColor.black.cgColor
        //枠線の太さ
        buttonTakePhoto.layer.borderWidth = 5.0
        //文字を消す
        buttonTakePhoto.setTitle("", for: .normal)
        //大きさ変更
        buttonTakePhoto.frame = CircleFromRect(x: buttonX, y: buttonY, radius: 50)
        //角を丸くする
        buttonTakePhoto.layer.cornerRadius = 50//width / 2, height / 2
    }

    func styleCameraRollButton(){
        buttonShowCameraRoll.setTitle("", for: .normal)
        //let picture = UIImage(systemName: "photo.stack.fill")
        let picture = UIImage(named: "test.png")
        buttonShowCameraRoll.setImage(picture, for: .normal)
    }
    
    
    //ボタンを押して、撮影モードを変更、ボタンのテキストを変更
    @IBAction func buttonTakePhotoPushed(_ sender: Any) {
//        self._captureSession.stopRunning()
//        self._captureSession.startRunning()
        
        //変更するか？　falseのとき押されていることになってる
        if takePhoto == true{
            //buttonTakePhoto.setTitle("停止中", for: .normal)
            self.buttonTakePhoto.layer.removeAllAnimations()
            UIView.animate(withDuration: 0.3, animations: {
                self.buttonTakePhoto.frame = self.CircleFromRect(x: self.buttonX, y: self.buttonY, radius: 50)
                self.buttonTakePhoto.layer.cornerRadius = 50
                self.buttonTakePhoto.alpha = 1.0
            })
        }else{
            //buttonTakePhoto.setTitle("撮影中", for: .normal)
            UIView.animate(withDuration: 0.3, animations: {
                self.buttonTakePhoto.layer.cornerRadius = 5
                self.buttonTakePhoto.frame = self.CircleFromRect(x: self.buttonX, y: self.buttonY, radius: 30)
            })
            UIView.animate(withDuration: 0.3,delay: 0.0, options: [.allowUserInteraction,.autoreverse,.repeat], animations: {
                self.buttonTakePhoto.alpha = 0.5
                //self.button1.layer.cornerRadius = 5
            })

        }
        takePhoto = !takePhoto
    }

    //シャッターボタン用　円の中心と半径を入力し、対応したRectを返す
    private func CircleFromRect(x:Int,y:Int, radius:Int) -> CGRect{
        return CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
    }

                           
                           
    
    @IBAction func segmentedValueChanged(_ sender: Any) {
        shutterSpeed = (segmentedControlShutter.selectedSegmentIndex + 1) * 10
    }
    //フロントカメラ、背面カメラ変更
    @IBAction func buttonCameraChangePushed(_ sender: Any) {
        self._captureSession.stopRunning()
        if self._videoDevice?.position == .back{
            
            setupVideo(camPos: .front, orientaiton: .portrait)
            // 録画開始
            //self._captureSession.startRunning()

        } else{
            setupVideo(camPos: .back, orientaiton: .portrait)
            // 録画開始
            //self._captureSession.startRunning()
        }
        //self._videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: camPos)
        
    }
    
    //カメラロール表示
    @IBAction func buttonPushedShowCameraRoll(_ sender: Any) {
        // フォトライブラリを表示
        present(picker, animated: true, completion: nil)
    }
    
    @IBAction func stepperValueChanged(_ sender: Any) {
        labelParsonNum.text = String(Int(stepperParsonNum.value))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        labelParsonNum.text = String(Int(stepperParsonNum.value))
        styleCaptureButton()
        styleCameraRollButton()
        setupVideo(camPos: .back, orientaiton: .portrait)
        // Do any additional setup after loading the view.
    }
    
    // 画面を回転させるかどうか
    override var shouldAutorotate: Bool {
        return false
    }
    
}

extension ViewController: AVCapturePhotoCaptureDelegate{
   // 撮影した画像データが生成されたときに呼び出されるデリゲートメソッド
   func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
       if let imageData = photo.fileDataRepresentation() {
           // Data型をUIImageオブジェクトに変換
           let uiImage = UIImage(data: imageData)
           // 写真ライブラリに画像を保存
           UIImageWriteToSavedPhotosAlbum(uiImage!, nil,nil,nil)
       }
   }
}

extension ViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true) // 追加: Cancel または Add ボタン押下で Picker が閉じられるようになる。
        
    }
}



