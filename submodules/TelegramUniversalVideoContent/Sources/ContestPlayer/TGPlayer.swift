import Foundation
import CoreMedia
import AVFoundation

final class TGPlayer {
    var rate: Float {
        get { _player?.rate ?? 0.0 }
        set {
            _player?.rate = newValue
            baseRate = newValue
        }
    }
    
    private(set) var currentTime: CMTime = .indefinite
    
    private(set) var isBuffering: Bool = false
    
    var isPlaying: Bool {
        !rate.isZero
    }
    
    private(set) var duration: TimeInterval?
    
    var volume: Float {
        get { _player?.volume ?? 0.0 }
        set { _player?.volume = newValue }
    }
    
    var onUpdate: (() -> Void)?
    
    var bufferedTime: TimeInterval {
        _player?.loadedProgress?.duration ?? 0.0
    }
    
    var bufferedTimeOffset: TimeInterval {
        _player?.loadedProgress?.offset ?? 0.0
    }
    
    var availableResolutions: [Int] {
        _player?.availableResolutions ?? []
    }
    
    var selectedResolution: Int? {
        didSet {
            if let selectedResolution {
                _player?.setManualResolution(selectedResolution)
            } else {
                _player?.setAutomaticResolution()
            }
        }
    }
    
    var currentResolution: Int? {
        _player?.currentResolution
    }
    
    // MARK: - Private props
    
    private var _player: TGPlayerInternal?
    private var _layer: TGPlayerLayer?
    
    private var baseRate: Float = 0.0
    private var didInitiallyStart = false
    private var isManuallyPaused = false
    private var isCompleted = false
    
    init() { }
    
    func attach(layer: TGPlayerLayer) {
        _layer = layer
    }
    
    func setContent(url: URL) {
        let player = TGPlayerInternal(url: url)
        _player = player
        
        player.output = .init { [weak self] error in
            print("Error: \(error)")
            self?._player?.seek(time: self?.currentTime ?? .zero)
        } onDurationUpdate: { [weak self] duration in
            self?.duration = duration.seconds.rounded(.down)
        } onTimeUpdate: { [weak self] playerTime, _ in
            self?.currentTime = playerTime
            self?.onUpdate?()
        } onStatusUpdate: { [weak self] status in
            guard let self else {
                return
            }
            
            DispatchQueue.main.async {
                switch status {
                case .finished:
                    self.isCompleted = true
                    self.isBuffering = false
                case .playing:
                    self.isCompleted = false
                    self.isBuffering = false
                case .buffering:
                    self.isCompleted = false
                    self.isBuffering = true
                }
                
                self.onUpdate?()
            }
        }
        
        if let _layer {
            player.attach(layer: _layer)
        }
        
        player.play()
    }
    
    func play() {
        DispatchQueue.main.async { [self] in
            if isCompleted {
                _player?.seek(time: .zero)
            } else if isManuallyPaused {
                _player?.rate = baseRate
            } else {
                _player?.play()
            }
            
            onUpdate?()
        }
    }
    
    func pause() {
        DispatchQueue.main.async { [self] in
            baseRate = rate
            _player?.rate = 0.0
            
            isManuallyPaused = true
            onUpdate?()
        }
    }
    
    func seek(to time: CMTime) {
        _player?.seek(time: time)
    }
    
    func purge() {
        _player?.purge()
    }
}
