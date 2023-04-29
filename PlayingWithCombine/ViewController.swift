import UIKit
import Combine

@MainActor
final class AsyncRunLoop {
  let taskSubject = CurrentValueSubject<Task<Void, Never>, Never>(Task {})
  var task: Task<Void, Never>? = nil
  
  init() {
    print("loop init")
    task = Task {
      for await task in taskSubject.values { await task.value }
    }
  }
  
  deinit { print("loop deinit") }
  
  func send(_ input: Task<Void, Never>) { taskSubject.send(input) }
  
  func cancel() { task?.cancel() }
}

@MainActor
final class ViewModel {
  @Published private(set) var title = ""
  private(set) var count = 0 {
    didSet { title = "count: \(count)" }
  }
  
  func incrementAsync() async {
    try? await Task.sleep(nanoseconds: 2_000_000_000)
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
    self.completion = completion
    super.init(nibName: nil, bundle: nil)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
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

    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: view.topAnchor, constant: 100),
      button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      presentButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      presentButton.centerYAnchor.constraint(equalTo: view.bottomAnchor, constant: -300),
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
  
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    completion?(viewModel.count)
  }
  
  deinit {
    subscriptions.forEach { $0.cancel() }
    Task { [runLoop] in await runLoop.cancel() }
    print("view controller deinit")
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
    
    
extension UIButton {
  func bind(to runLoop: AsyncRunLoop, action: @escaping () async -> Void) {
    addAction(UIAction(handler: { _ in
      runLoop.send(Task<Void, Never> { await action() })
    }), for: .touchUpInside)
  }
}
