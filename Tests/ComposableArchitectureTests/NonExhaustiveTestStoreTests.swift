import ComposableArchitecture
import XCTest

class NETSTests: XCTestCase {

  func testSend() {
    let mainQueue = DispatchQueue.test
    struct State: Equatable {
      var count = 0
      var ignored = ""
    }
    enum Action: Equatable { case incr, decr, response1, response2 }
    let store = BCTestStore(
      initialState: State(),
      reducer: Reducer<State, Action, Void> { state, action, _ in
        switch action {
        case .incr:
          state.count += 1
          state.ignored += "!"
          return .concatenate(
            Effect(value: .response1)
            .receive(on: mainQueue)
            .eraseToEffect(),
            Effect(value: .response2)
              .receive(on: mainQueue)
              .eraseToEffect()
            )
        case .decr:
          state.count -= 1
          state.ignored += "?"
          return .none
        case .response1:
          state.count += 2
          return .none
        case .response2:
          state.count += 4
          return .none
        }
      },
      environment: ()
    )

    store.nonExhaustiveSend(.incr) {
      $0.count = 2
    }
    mainQueue.advance()
    mainQueue.advance()

    store.nonExhaustiveReceive(.response2) {
      $0.count = 7
    }
  }
}


class BCTestStore<State, LocalState, Action, LocalAction, Environment>
: TestStore<State, LocalState, Action, LocalAction, Environment> {

  deinit {
    self.ignoreReceivedActions(strict: false)
    self.cancelInflightEffects()
  }
}
extension BCTestStore where State == LocalState, Action == LocalAction {
  convenience init(
    initialState: State,
    reducer: Reducer<State, Action, Environment>,
    environment: Environment,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    self.init(
      initialState: initialState,
      reducer: reducer,
      environment: environment,
      file: file,
      line: line
    )
  }

}


import XCTest
extension BCTestStore where LocalState: Equatable {
  func nonExhaustiveSend(
    _ action: LocalAction,
    _ updateExpectingResult: ((inout LocalState) throws -> Void)? = nil,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    do {
      self.ignoreReceivedActions(strict: false)

      XCTExpectFailure {
        self.send(action, updateExpectingResult, file: file, line: line)
      }

      var updated = self.toLocalState(self.state)
      if let updateExpectingResult {
        try updateExpectingResult(&updated)
        XCTAssertEqual(self.toLocalState(self.state), updated, file: file, line: line)
      }
    } catch {
      // TODO: XCTFail
    }
  }
}
extension BCTestStore where LocalState: Equatable, Action: Equatable {
  func nonExhaustiveReceive(
    _ expectedAction: Action,
    _ updateExpectingResult: ((inout LocalState) throws -> Void)? = nil,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    do {
      guard receivedActions.contains(where: { $0.action == expectedAction }) else {
        XCTFail(
        """
        Expected to receive an action \(expectedAction), but didn't get one.
        """,
        file: file, line: line
        )
        return
      }


      while
        let receivedAction = self.receivedActions.first,
        receivedAction.action != expectedAction
      {
        XCTExpectFailure(strict: false) {
          self.receive(receivedAction.action, file: file, line: line)
        }
      }

      XCTExpectFailure(strict: false) {
        self.receive(self.receivedActions.first!.action, file: file, line: line)
      }

      var updated = self.toLocalState(self.state)
      if let updateExpectingResult {
        try updateExpectingResult(&updated)
        XCTAssertEqual(self.toLocalState(self.state), updated, file: file, line: line)
      }
    } catch {
      // TODO: XCTFail
    }
  }
}
