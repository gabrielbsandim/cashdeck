import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private let privacyCover = PrivacyCover()

  override init() {
    super.init()
    privacyCover.observe()
  }
}

/// Blurs balances out of the app switcher snapshot. Uses notifications because
/// overriding the scene callbacks would drop the lifecycle Flutter forwards.
final class PrivacyCover {
  private var cover: UIView?
  private var observers: [NSObjectProtocol] = []

  func observe() {
    let center = NotificationCenter.default
    observers = [
      center.addObserver(
        forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main
      ) { [weak self] note in
        self?.show(on: note.object as? UIWindowScene)
      },
      center.addObserver(
        forName: UIScene.willEnterForegroundNotification, object: nil, queue: .main
      ) { [weak self] _ in
        self?.hide()
      },
    ]
  }

  deinit {
    observers.forEach(NotificationCenter.default.removeObserver)
  }

  private func show(on scene: UIWindowScene?) {
    guard cover == nil, let window = scene?.windows.first else { return }
    let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    view.frame = window.bounds
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(view)
    cover = view
  }

  private func hide() {
    cover?.removeFromSuperview()
    cover = nil
  }
}
