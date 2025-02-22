import RxSwift
import XCTest

@_spi(Internals) import RxComposableArchitecture

internal final class EffectCancellationTests: XCTestCase {
    struct CancelID: Hashable {}
    private var disposeBag = DisposeBag()

    override internal func tearDown() {
        super.tearDown()
        disposeBag = DisposeBag()
    }

    internal func testCancellation() {
        var values: [Int] = []

        let subject = PublishSubject<Int>()
        let effect = Effect(subject)
            .cancellable(id: CancelID())

        effect.subscribe(onNext: { values.append($0) })
            .disposed(by: disposeBag)

        XCTAssertEqual(values, [])
        subject.onNext(1)
        XCTAssertEqual(values, [1])
        subject.onNext(2)
        XCTAssertEqual(values, [1, 2])

        Effect<Never>.cancel(id: CancelID())
            .subscribe()
            .disposed(by: disposeBag)

        subject.onNext(3)
        XCTAssertEqual(values, [1, 2])
    }

    internal func testCancelInFlight() {
        var values: [Int] = []

        let subject = PublishSubject<Int>()
        Effect(subject)
            .cancellable(id: CancelID(), cancelInFlight: true)
            .subscribe(onNext: { values.append($0) })
            .disposed(by: disposeBag)

        XCTAssertEqual(values, [])
        subject.onNext(1)
        XCTAssertEqual(values, [1])
        subject.onNext(2)
        XCTAssertEqual(values, [1, 2])

        Effect(subject)
            .cancellable(id: CancelID(), cancelInFlight: true)
            .subscribe(onNext: { values.append($0) })
            .disposed(by: disposeBag)

        subject.onNext(3)
        XCTAssertEqual(values, [1, 2, 3])
        subject.onNext(4)
        XCTAssertEqual(values, [1, 2, 3, 4])
    }

    internal func testCancellationAfterDelay() {
        var value: Int?

        Observable.just(1)
            .delay(.milliseconds(500), scheduler: MainScheduler.instance)
            .eraseToEffect()
            .cancellable(id: CancelID())
            .subscribe(onNext: { value = $0 })
            .disposed(by: disposeBag)

        XCTAssertEqual(value, nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            _ = Effect<Never>.cancel(id: CancelID())
                .subscribe()
                .disposed(by: self.disposeBag)
        }

        _ = XCTWaiter.wait(for: [expectation(description: "")], timeout: 0.1)

        XCTAssertEqual(value, nil)
    }

    internal func testCancellationAfterDelay_WithTestScheduler() {
        let scheduler = TestScheduler(initialClock: 0)

        var value: Int?

        Observable.just(1)
            .delay(.seconds(2), scheduler: scheduler)
            .eraseToEffect()
            .cancellable(id: CancelID())
            .subscribe(onNext: { value = $0 })
            .disposed(by: disposeBag)

        XCTAssertEqual(value, nil)

        scheduler.advance(by: .seconds(1))

        Effect<Never>.cancel(id: CancelID())
            .subscribe()
            .disposed(by: disposeBag)

        scheduler.run()

        XCTAssertEqual(value, nil)
    }

    internal func testCancellablesCleanUp_OnComplete() {
        let id = UUID()
        Observable.just(1)
            .eraseToEffect()
            .cancellable(id: id)
            .subscribe()
            .disposed(by: disposeBag)

        XCTAssertNoDifference([:], _cancellationCancellables)
    }

    internal func testCancellablesCleanUp_OnCancel() {
        let id = UUID()
        
        let scheduler = TestScheduler(initialClock: 0)

        Observable.just(1)
            .delay(.seconds(1), scheduler: scheduler)
            .eraseToEffect()
            .cancellable(id: id)
            .subscribe()
            .disposed(by: disposeBag)

        Effect<Never>.cancel(id: id)
            .subscribe()
            .disposed(by: disposeBag)
        
        XCTAssertTrue(_cancellationCancellables.isEmpty)
    }

    internal func testDoubleCancellation() {
        var values: [Int] = []

        let subject = PublishSubject<Int>()
        let effect = Effect(subject)
            .cancellable(id: CancelID())
            .cancellable(id: CancelID())

        effect
            .subscribe(onNext: { values.append($0) })
            .disposed(by: disposeBag)

        XCTAssertEqual(values, [])
        subject.onNext(1)
        XCTAssertEqual(values, [1])

        Effect<Never>.cancel(id: CancelID())
            .subscribe()
            .disposed(by: disposeBag)

        subject.onNext(2)
        XCTAssertEqual(values, [1])
    }

    internal func testCompleteBeforeCancellation() {
        var values: [Int] = []

        let subject = PublishSubject<Int>()
        let effect = Effect(subject)
            .cancellable(id: CancelID())

        effect
            .subscribe(onNext: { values.append($0) })
            .disposed(by: disposeBag)

        subject.onNext(1)
        XCTAssertEqual(values, [1])

        subject.onCompleted()
        XCTAssertEqual(values, [1])

        Effect<Never>.cancel(id: CancelID())
            .subscribe()
            .disposed(by: disposeBag)

        XCTAssertEqual(values, [1])
    }

    internal func testNestedCancels() {
        let id = UUID()
        
        var effect = Observable<Void>.never()
            .eraseToEffect()
            .cancellable(id: 1)

        for _ in 1 ... .random(in: 1 ... 1000) {
            effect = effect.cancellable(id: id)
        }

        effect
            .subscribe(onNext: { _ in })
            .disposed(by: disposeBag)

        disposeBag = DisposeBag()

        XCTAssertNoDifference([:], _cancellationCancellables)
    }

    internal func testSharedId() {
        let scheduler = TestScheduler(initialClock: 0)

        let effect1 = Observable.just(1)
            .delay(.seconds(1), scheduler: scheduler)
            .eraseToEffect()
            .cancellable(id: "id")

        let effect2 = Observable.just(2)
            .delay(.seconds(2), scheduler: scheduler)
            .eraseToEffect()
            .cancellable(id: "id")

        var expectedOutput: [Int] = []
        effect1
            .subscribe(onNext: { expectedOutput.append($0) })
            .disposed(by: disposeBag)
        effect2
            .subscribe(onNext: { expectedOutput.append($0) })
            .disposed(by: disposeBag)

        XCTAssertEqual(expectedOutput, [])
        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(expectedOutput, [1])
        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(expectedOutput, [1, 2])
    }

    internal func testImmediateCancellation() {
        let scheduler = TestScheduler(initialClock: 0)

        var expectedOutput: [Int] = []
        // Don't hold onto cancellable so that it is deallocated immediately.
        let d = Observable.deferred { .just(1) }
            .delay(.seconds(1), scheduler: scheduler)
            .eraseToEffect()
            .cancellable(id: "id")
            .subscribe(onNext: { expectedOutput.append($0) })
        d.dispose()

        XCTAssertEqual(expectedOutput, [])
        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(expectedOutput, [])
    }
    
    internal func testNestedMergeCancellation() {
        let effect = Effect<Int>.merge(
            Observable.of(1, 2)
                .eraseToEffect()
                .cancellable(id: 1)
        )
            .cancellable(id: 2)

        var output: [Int] = []
        effect
            .subscribe(onNext: { output.append($0) })
            .disposed(by: disposeBag)

        XCTAssertEqual(output, [1, 2])
    }

    internal func testMultipleCancellations() {
        let scheduler = TestScheduler(initialClock: 0)
        var output: [AnyHashable] = []

        struct A: Hashable {}
        struct B: Hashable {}
        struct C: Hashable {}

        let ids: [AnyHashable] = [A(), B(), C()]
        let effects = ids.map { id in
            Observable.just(id)
                .delay(.seconds(1), scheduler: scheduler)
                .eraseToEffect()
                .cancellable(id: id)
        }

        Effect<AnyHashable>.merge(effects)
            .subscribe(onNext: { output.append($0) })
            .disposed(by: disposeBag)

        Effect<AnyHashable>
            .cancel(ids: [A(), C()])
            .subscribe(onNext: { _ in })
            .disposed(by: disposeBag)

        scheduler.advance(by: .seconds(1))
        XCTAssertNoDifference(output, [B()])
    }

}
