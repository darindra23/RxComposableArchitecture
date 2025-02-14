import RxSwift

extension Effect: ObservableType {
    public typealias Element = Action
    
    public func subscribe<Observer>(_ observer: Observer) -> Disposable where Observer : ObserverType, Action == Observer.Element {
        self.observable.subscribe(observer)
    }
    
    public var observable: Observable<Action> {
        switch self.operation {
        case .none:
            return .empty()
        case let .observable(observable):
            return observable
        case let .run(priority, operation):
            return Observable.create { observer in
                let task = Task(priority: priority) { @MainActor in
                    defer { observer.onCompleted() }
                    let send = Send { action in
                        observer.onNext(action)
                    }
                    await operation(send)
                }
                return Disposables.create {
                    task.cancel()
                }
            }
        }
    }
    
    /// Initializes an effect that wraps a publisher.
    ///
    /// > Important: This Combine interface has been soft-deprecated in favor of Swift concurrency.
    /// > Prefer performing asynchronous work directly in
    /// > ``Effect/run(priority:operation:catch:file:fileID:line:)`` by adopting a non-Combine
    /// > interface, or by iterating over the publisher's asynchronous sequence of `values`:
    /// >
    /// > ```swift
    /// > return .run { send in
    /// >   for await value in publisher.values {
    /// >     send(.response(value))
    /// >   }
    /// > }
    /// > ```
    ///
    /// - Parameter publisher: A publisher.
    @available(iOS, deprecated: 9999.0, message: "Iterate over 'Observable.values' in an 'Effect.run', instead.")
    public init<O: Observable<Action>>(_ observable: O) where O.Element == Action {
        self.operation = .observable(observable)
    }
    
    /// Initializes an effect that immediately emits the value passed in.
    ///
    /// - Parameter value: The value that is immediately emitted by the effect.
    @available(iOS, deprecated: 9999.0, message: "Wrap the value in 'Effect.task', instead.")
    public init(value: Action) {
        self.init(Observable.just(value))
    }
    
    /// Initializes an effect that immediately fails with the error passed in.
    ///
    /// - Parameter error: The error that is immediately emitted by the effect.
    @available(iOS, deprecated: 9999.0, message: "Throw and catch errors directly in 'Effect.task' and 'Effect.run', instead.")
    public init(error: Error) {
        self.init(operation: .observable(Observable.error(error)))
    }
    
    /// Creates an effect that can supply a single value asynchronously in the future.
    ///
    /// This can be helpful for converting APIs that are callback-based into ones that deal with
    /// ``Effect``s.
    ///
    /// For example, to create an effect that delivers an integer after waiting a second:
    ///
    /// ```swift
    /// Effect<Int, Never>.future { callback in
    ///   DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    ///     callback(.success(42))
    ///   }
    /// }
    /// ```
    ///
    /// Note that you can only deliver a single value to the `callback`. If you send more they will be
    /// discarded:
    ///
    /// ```swift
    /// Effect<Int, Never>.future { callback in
    ///   DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    ///     callback(.success(42))
    ///     callback(.success(1729)) // Will not be emitted by the effect
    ///   }
    /// }
    /// ```
    ///
    ///  If you need to deliver more than one value to the effect, you should use the ``Effect``
    ///  initializer that accepts a ``Subscriber`` value.
    ///
    /// - Parameter attemptToFulfill: A closure that takes a `callback` as an argument which can be
    ///   used to feed it `Result<Output, Failure>` values.
    @available(iOS, deprecated: 9999.0, message: "Use 'Effect.task', instead.")
    public static func future(
        _ attemptToFulfill: @escaping (@escaping (Result<Action, Error>) -> Void) -> Void
    ) -> Self {
        let dependencies = DependencyValues._current
        return Observable.deferred {
            DependencyValues.$_current.withValue(dependencies) {
                Observable<Action>.create { observer in
                    attemptToFulfill { result in
                        switch result {
                        case let .success(output):
                            observer.onNext(output)
                            observer.onCompleted()
                        case let .failure(error):
                            observer.onError(error)
                        }
                    }
                    return Disposables.create()
                }
            }
        }
        .eraseToEffect()
    }
    
    /// Initializes an effect that lazily executes some work in the real world and synchronously sends
    /// that data back into the store.
    ///
    /// For example, to load a user from some JSON on the disk, one can wrap that work in an effect:
    ///
    /// ```swift
    /// Effect<User, Error>.result {
    ///   let fileUrl = URL(
    ///     fileURLWithPath: NSSearchPathForDirectoriesInDomains(
    ///       .documentDirectory, .userDomainMask, true
    ///     )[0]
    ///   )
    ///   .appendingPathComponent("user.json")
    ///
    ///   let result = Result<User, Error> {
    ///     let data = try Data(contentsOf: fileUrl)
    ///     return try JSONDecoder().decode(User.self, from: $0)
    ///   }
    ///
    ///   return result
    /// }
    /// ```
    ///
    /// - Parameter attemptToFulfill: A closure encapsulating some work to execute in the real world.
    /// - Returns: An effect.
    @available(iOS, deprecated: 9999.0, message: "Use 'Effect.task', instead.")
    public static func result(_ attemptToFulfill: @escaping () -> Result<Action, Error>) -> Self {
        .future { $0(attemptToFulfill()) }
    }
    
    /// Initializes an effect from a callback that can send as many values as it wants, and can send
    /// a completion.
    ///
    /// This initializer is useful for bridging callback APIs, delegate APIs, and manager APIs to the
    /// ``Effect`` type. One can wrap those APIs in an Effect so that its events are sent through the
    /// effect, which allows the reducer to handle them.
    ///
    /// For example, one can create an effect to ask for access to `MPMediaLibrary`. It can start by
    /// sending the current status immediately, and then if the current status is `notDetermined` it
    /// can request authorization, and once a status is received it can send that back to the effect:
    ///
    /// ```swift
    /// Effect.run { subscriber in
    ///   subscriber.send(MPMediaLibrary.authorizationStatus())
    ///
    ///   guard MPMediaLibrary.authorizationStatus() == .notDetermined else {
    ///     subscriber.send(completion: .finished)
    ///     return AnyCancellable {}
    ///   }
    ///
    ///   MPMediaLibrary.requestAuthorization { status in
    ///     subscriber.send(status)
    ///     subscriber.send(completion: .finished)
    ///   }
    ///   return AnyCancellable {
    ///     // Typically clean up resources that were created here, but this effect doesn't
    ///     // have any.
    ///   }
    /// }
    /// ```
    ///
    /// - Parameter work: A closure that accepts a ``Subscriber`` value and returns a cancellable.
    ///   When the ``Effect`` is completed, the cancellable will be used to clean up any resources
    ///   created when the effect was started.
    @available(iOS, deprecated: 9999.0, message: "Use the async version of 'Effect.run', instead.")
    public static func run(
        _ work: @escaping (AnyObserver<Action>) -> Disposable
    ) -> Self {
        let dependencies = DependencyValues._current
        return Observable.create { observer in
            DependencyValues.$_current.withValue(dependencies) {
                work(observer)
            }
        }
        .eraseToEffect()
    }
    
    /// Creates an effect that executes some work in the real world that doesn't need to feed data
    /// back into the store. If an error is thrown, the effect will complete and the error will be
    /// ignored.
    ///
    /// - Parameter work: A closure encapsulating some work to execute in the real world.
    /// - Returns: An effect.
    @available(iOS, deprecated: 9999.0, message: "Use the async version, instead.")
    public static func fireAndForget(_ work: @escaping () -> Void) -> Self {
        let dependencies = DependencyValues._current
        return Observable.deferred {
            DependencyValues.$_current.withValue(dependencies) {
                work()
                return Observable<Action>.empty()
            }
        }
        .eraseToEffect()
    }
    
    public func flatMap<T: ObservableType>(_ transform: @escaping (Action) -> T) -> Effect<T.Element> {
        switch self.operation {
        case let .observable(observable):
            let dependencies = DependencyValues._current
            let transform = { action in
                DependencyValues.$_current.withValue(dependencies) {
                    transform(action)
                }
            }
            return observable.flatMap(transform).eraseToEffect()
        default:
            return .none
        }
    }
}

extension ObservableType where Element == Never {
    public func fireAndForget<T>() -> Observable<T> {
        func absurd<A>(_: Never) -> A {}
        return map(absurd)
    }
}

extension ObservableType {
    /// Turns any publisher into an `Effect`.
    ///
    /// This can be useful for when you perform a chain of publisher transformations in a reducer, and
    /// you need to convert that publisher to an effect so that you can return it from the reducer:
    ///
    ///     case .buttonTapped:
    ///       return fetchUser(id: 1)
    ///         .filter(\.isAdmin)
    ///         .eraseToEffect()
    ///
    /// - Returns: An effect that wraps `self`.
    public func eraseToEffect() -> Effect<Element> {
        Effect(asObservable())
    }
    
    /// Turns any publisher into an ``Effect``.
    ///
    /// This is a convenience operator for writing ``Effect/eraseToEffect()`` followed by
    /// ``Effect/map(_:)-28ghh`.
    ///
    /// ```swift
    /// case .buttonTapped:
    ///   return fetchUser(id: 1)
    ///     .filter(\.isAdmin)
    ///     .eraseToEffect(ProfileAction.adminUserFetched)
    /// ```
    ///
    /// - Parameters:
    ///   - transform: A mapping function that converts `Output` to another type.
    /// - Returns: An effect that wraps `self` after mapping `Output` values.
    @available(iOS, deprecated: 9999.0, message: "Iterate over 'Publisher.values' in an 'Effect.run', instead.")
    public func eraseToEffect<T>(
        _ transform: @escaping (Element) -> T
    ) -> Effect<T> {
        self.map(transform)
            .eraseToEffect()
    }
    
    /// Turns any publisher into an ``Effect`` that cannot fail by wrapping its output and failure in
    /// a result.
    ///
    /// This can be useful when you are working with a failing API but want to deliver its data to an
    /// action that handles both success and failure.
    ///
    /// ```swift
    /// case .buttonTapped:
    ///   return self.apiClient.fetchUser(id: 1)
    ///     .catchToEffect()
    ///     .map(ProfileAction.userResponse)
    /// ```
    ///
    /// - Returns: An effect that wraps `self`.
    @available(iOS, deprecated: 9999.0, message: "Iterate over 'Publisher.values' in an 'Effect.run', instead.")
    public func catchToEffect() -> Effect<Result<Element, Error>> {
        self.catchToEffect { $0 }
    }
    
    /// Turns any publisher into an ``Effect`` that cannot fail by wrapping its output and failure
    /// into a result and then applying passed in function to it.
    ///
    /// This is a convenience operator for writing ``Effect/eraseToEffect()`` followed by
    /// ``Effect/map(_:)-28ghh`.
    ///
    /// ```swift
    /// case .buttonTapped:
    ///   return self.apiClient.fetchUser(id: 1)
    ///     .catchToEffect(ProfileAction.userResponse)
    /// ```
    ///
    /// - Parameters:
    ///   - transform: A mapping function that converts `Result<Output,Failure>` to another type.
    /// - Returns: An effect that wraps `self`.
    @available(iOS, deprecated: 9999.0, message: "Iterate over 'Publisher.values' in an 'Effect.run', instead.")
    public func catchToEffect<T>(
        _ transform: @escaping (Result<Element, Error>) -> T
    ) -> Effect<T> {
        let dependencies = DependencyValues._current
        let transform = { action in
            DependencyValues.$_current.withValue(dependencies) {
                transform(action)
            }
        }
        return map { transform(.success($0)) }
            .catchError { Observable.just(transform(.failure($0))) }
            .eraseToEffect()
    }
    
    /// Turns any publisher into an `Effect` for any output and failure type by ignoring all output
    /// and any failure.
    ///
    /// This is useful for times you want to fire off an effect but don't want to feed any data back
    /// into the system.
    ///
    ///     case .buttonTapped:
    ///       return analyticsClient.track("Button Tapped")
    ///         .fireAndForget()
    ///
    /// - Returns: An effect that never produces output or errors.
    public func fireAndForget<NewOutput>(
        outputType _: NewOutput.Type = NewOutput.self
    ) -> Effect<NewOutput> {
        return flatMap { _ in Observable.empty() }
            .eraseToEffect()
    }
}
