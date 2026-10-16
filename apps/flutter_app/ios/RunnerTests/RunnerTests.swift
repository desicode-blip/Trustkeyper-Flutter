import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  private let appID = "1:123456789:ios:synthetic"
  private let callback = URL(string: "app-1-123456789-ios-synthetic://firebaseauth/link?deep_link_id=synthetic")!

  func testCallbackGoesToFirebaseInsteadOfThePageRouter() {
    var forwarded: [URL] = []
    let plugin = FirebaseAuthCallbackPlugin(appID: { self.appID }, forwardToAuth: { forwarded.append($0) })
    XCTAssertTrue(plugin.handleCallbacks([callback]))
    XCTAssertEqual(forwarded, [callback])
  }

  func testDuplicateOrExpiredCallbacksRemainConsumedWhenFirebaseHasNoPendingRequest() {
    var attempts = 0
    let plugin = FirebaseAuthCallbackPlugin(appID: { self.appID }, forwardToAuth: { _ in attempts += 1 })
    XCTAssertTrue(plugin.handleCallbacks([callback]))
    XCTAssertTrue(plugin.handleCallbacks([callback]))
    XCTAssertEqual(attempts, 2)
  }

  func testNormalAppAndBrowserLinksAreNotConsumed() {
    var attempts = 0
    let plugin = FirebaseAuthCallbackPlugin(appID: { self.appID }, forwardToAuth: { _ in attempts += 1 })
    for value in ["trustkeyper://broker", "https://trustkeyper.web.app/documents/request?token=synthetic",
      "app-1-123456789-ios-other://firebaseauth/link", "app-1-123456789-ios-synthetic://other/link",
      "app-1-123456789-ios-synthetic://firebaseauth/unrelated"] {
      XCTAssertFalse(plugin.handleCallbacks([URL(string: value)!]))
    }
    XCTAssertEqual(attempts, 0)
  }

  func testEveryCallbackInTheBatchIsForwarded() {
    var forwarded: [URL] = []
    let plugin = FirebaseAuthCallbackPlugin(appID: { self.appID }, forwardToAuth: { forwarded.append($0) })
    let second = URL(string: "app-1-123456789-ios-synthetic://firebaseauth/link?deep_link_id=second")!
    XCTAssertTrue(plugin.handleCallbacks([callback, second]))
    XCTAssertEqual(forwarded, [callback, second])
  }

  func testMissingFirebaseConfigurationAndEmptyColdLaunchDoNotClaimLinks() {
    let plugin = FirebaseAuthCallbackPlugin(appID: { nil }, forwardToAuth: { _ in XCTFail("No Firebase configuration") })
    XCTAssertFalse(plugin.handleCallbacks([callback]))
    XCTAssertFalse(plugin.handleCallbacks([]))
    let configured = FirebaseAuthCallbackPlugin(appID: { self.appID }, forwardToAuth: { _ in XCTFail("No URLs") })
    XCTAssertFalse(configured.handleCallbacks([]))
  }

}
