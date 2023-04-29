import UIKit
import Combine

@MainActor
final class AsyncRunLoop {
  typealias Action = () async -> Void
    
  private var subject: AsyncStream<Action>.Continuation!
  private var task: Task<Void, Never>? = nil
  
  init() {
    print("runloop init")
    let stream = AsyncStream { self.subject = $0 }
    task = Task { for await action in stream { await action() } }
  }
  
  deinit { print("runloop deinit") }
  
  func send(_ action: @escaping Action) { subject.yield(action) }
  func cancel() { task?.cancel() }
}

@MainActor
protocol AsyncRunLoopBindable {
  func bind(to runLoop: AsyncRunLoop, action: @escaping AsyncRunLoop.Action)
}

@MainActor
final class ViewModel {
  @Published private(set) var isBusy = false
  @Published private(set) var title = ""
  private(set) var count = 0 {
    didSet { title = "count: \(count)" }
  }
  
  func incrementAsync() async {
    isBusy = true
    defer { isBusy = false }
    try? await Task.sleep(nanoseconds: 2_000_000_000)
    print("incrementAsync")
    count += 1
  }

  func increment(by count: Int = 1) {
    self.count += count
  }
}

@MainActor
final class ViewController: UIViewController {

  let runLoop = AsyncRunLoop()
  let viewModel = ViewModel()
  var subscriptions = Set<AnyCancellable>()
  
  let completion: ((Int) -> Void)?
  
  init(completion: @escaping (Int) -> Void) {
    print("viewcontroller init")
    self.completion = completion
    super.init(nibName: nil, bundle: nil)
  }
  
  required init?(coder: NSCoder) { fatalError() }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .white
    
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(label)

    let button = UIButton()
    button.setTitleColor(.black, for: .normal)
    button.setTitle("Increment", for: .normal)
    button.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(button)

    let presentButton = UIButton()
    presentButton.setTitleColor(.black, for: .normal)
    presentButton.setTitle("Present new", for: .normal)
    presentButton.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(presentButton)
    
    let spinner = UIActivityIndicatorView()
    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.hidesWhenStopped = true
    view.addSubview(spinner)
    viewModel.$isBusy
      .sink { $0 ? spinner.startAnimating() : spinner.stopAnimating() }
      .store(in: &subscriptions)
    
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: view.topAnchor, constant: 100),
      button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      presentButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      presentButton.centerYAnchor.constraint(equalTo: view.bottomAnchor, constant: -300),
      spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: view.topAnchor, constant: 300),
    ])

    viewModel.$title
      .map { $0 }
      .assign(to: \.text, on: label)
      .store(in: &subscriptions)
    

    button.bind(to: runLoop, action: viewModel.incrementAsync)

    presentButton.bind(to: runLoop) { [weak self] in
      guard let self else { return }
      let newCount = await self.presentNewCounter()
      self.viewModel.increment(by: newCount)
    }
  }
    
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    completion?(viewModel.count)
    runLoop.cancel()
  }
  
  deinit {
    print("viewcontroller deinit")
    subscriptions.forEach { $0.cancel() }
  }
}

// MARK: - UI Actions

extension ViewController {
  
  func presentNewCounter() async -> Int {
    await withCheckedContinuation { continuation in
      present(ViewController { count in
        continuation.resume(with: .success(count))
      }, animated: true)
    }
  }

}

extension UIButton: AsyncRunLoopBindable {
  func bind(to runLoop: AsyncRunLoop, action: @escaping () async -> Void) {
    addAction(UIAction(handler: { _ in
      runLoop.send(action)
    }), for: .touchUpInside)
  }
}
