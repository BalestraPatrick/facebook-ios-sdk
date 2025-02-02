/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSDKCoreKit
import TestTools
import XCTest

class ApplicationDelegateTests: XCTestCase { // swiftlint:disable:this type_body_length

  var center = TestNotificationCenter()
  var featureChecker = TestFeatureManager()
  var appEvents = TestAppEvents()
  var store = UserDefaultsSpy()
  let observer = TestApplicationDelegateObserver()
  let settings = TestSettings()
  let backgroundEventLogger = TestBackgroundEventLogger(
    infoDictionaryProvider: TestBundle(),
    eventLogger: TestAppEvents()
  )
  let serverConfigurationProvider = TestServerConfigurationProvider()
  let bitmaskKey = "com.facebook.sdk.kits.bitmask"
  let paymentObserver = TestPaymentObserver()
  lazy var profile = Profile(
    userID: name,
    firstName: nil,
    middleName: nil,
    lastName: nil,
    name: nil,
    linkURL: nil,
    refreshDate: nil
  )
  lazy var delegate = ApplicationDelegate(
    notificationCenter: center,
    tokenWallet: TestAccessTokenWallet.self,
    settings: settings,
    featureChecker: featureChecker,
    appEvents: appEvents,
    serverConfigurationProvider: serverConfigurationProvider,
    store: store,
    authenticationTokenWallet: TestAuthenticationTokenWallet.self,
    profileProvider: TestProfileProvider.self,
    backgroundEventLogger: backgroundEventLogger,
    paymentObserver: paymentObserver
  )

  override class func setUp() {
    super.setUp()

    resetTestData()
  }

  override func setUp() {
    super.setUp()

    ApplicationDelegate.reset()
  }

  override func tearDown() {
    super.tearDown()

    ApplicationDelegateTests.resetTestData()
    settings.reset()
  }

  static func resetTestData() {
    TestAccessTokenWallet.reset()
    TestAuthenticationTokenWallet.reset()
    TestGateKeeperManager.reset()
    TestProfileProvider.reset()
  }

  func testDefaultDependencies() {
    delegate = ApplicationDelegate.shared

    XCTAssertEqual(
      delegate.notificationObserver as? NotificationCenter,
      NotificationCenter.default,
      "Should use the default system notification center"
    )
    XCTAssertTrue(
      delegate.tokenWallet is AccessToken.Type,
      "Should use the expected default access token setter"
    )
    XCTAssertEqual(
      delegate.featureChecker as? FeatureManager,
      FeatureManager.shared,
      "Should use the default feature checker"
    )
    XCTAssertEqual(
      delegate.appEvents as? AppEvents,
      AppEvents.shared,
      "Should use the expected default app events instance"
    )
    XCTAssertTrue(
      delegate.serverConfigurationProvider is ServerConfigurationManager,
      "Should use the expected default server configuration provider"
    )
    XCTAssertEqual(
      delegate.store as? UserDefaults,
      UserDefaults.standard,
      "Should use the expected default persistent store"
    )
    XCTAssertTrue(
      delegate.authenticationTokenWallet is AuthenticationToken.Type,
      "Should use the expected default access token setter"
    )
    XCTAssertTrue(
      delegate.settings === Settings.shared,
      "Should use the expected default settings"
    )
    XCTAssertTrue(
      delegate.paymentObserver is PaymentObserver,
      "Should use the expected concrete payment observer"
    )
  }

  func testCreatingWithDependencies() {
    XCTAssertTrue(
      delegate.notificationObserver is TestNotificationCenter,
      "Should be able to create with a custom notification center"
    )
    XCTAssertTrue(
      delegate.tokenWallet is TestAccessTokenWallet.Type,
      "Should be able to create with a custom access token setter"
    )
    XCTAssertEqual(
      delegate.featureChecker as? TestFeatureManager,
      featureChecker,
      "Should be able to create with a feature checker"
    )
    XCTAssertEqual(
      delegate.appEvents as? TestAppEvents,
      appEvents,
      "Should be able to create with an app events instance"
    )
    XCTAssertTrue(
      delegate.serverConfigurationProvider is TestServerConfigurationProvider,
      "Should be able to create with a server configuration provider"
    )
    XCTAssertEqual(
      delegate.store as? UserDefaultsSpy,
      store,
      "Should be able to create with a persistent store"
    )
    XCTAssertTrue(
      delegate.authenticationTokenWallet is TestAuthenticationTokenWallet.Type,
      "Should be able to create with a custom access token setter"
    )
    XCTAssertEqual(
      delegate.settings as? TestSettings,
      settings,
      "Should be able to create with custom settings"
    )
    XCTAssertEqual(
      delegate.backgroundEventLogger as? TestBackgroundEventLogger,
      backgroundEventLogger,
      "Should be able to create with custom background event logger"
    )
  }

  func testCreatingSetsExpirer() throws {
    let delegateCenter = try XCTUnwrap(delegate.notificationObserver as? TestNotificationCenter)
    let expirerCenter = try XCTUnwrap(delegate.accessTokenExpirer.notificationCenter as? TestNotificationCenter)

    XCTAssertEqual(
      expirerCenter,
      delegateCenter,
      "Should create the token expirer using the delegate's notification center"
    )
  }

  // MARK: - Initializing SDK

  func testInitializingSdkTriggersApplicationLifecycleNotificationsForAppEvents() {
    delegate.initializeSDK(launchOptions: [:])

    XCTAssertTrue(
      appEvents.wasStartObservingApplicationLifecycleNotificationsCalled,
      "Should have app events start observing application lifecycle notifications upon initialization"
    )
  }

  func testInitializingSDKLogsAppEvent() {
    store.setValue(1, forKey: bitmaskKey)

    delegate._logSDKInitialize()

    XCTAssertEqual(
      appEvents.capturedEventName,
      .initializeSDK
    )
    XCTAssertFalse(appEvents.capturedIsImplicitlyLogged)
  }

  func testInitializingSdkObservesSystemNotifications() {
    delegate.initializeSDK(launchOptions: [:])

    XCTAssertTrue(
      center.capturedAddObserverInvocations.contains(
        TestNotificationCenter.ObserverEvidence(
          observer: delegate as Any,
          name: UIApplication.didEnterBackgroundNotification,
          selector: #selector(ApplicationDelegate.applicationDidEnterBackground(_:)),
          object: nil
        )
      ),
      "Should start observing application backgrounding upon initialization"
    )
    XCTAssertTrue(
      center.capturedAddObserverInvocations.contains(
        TestNotificationCenter.ObserverEvidence(
          observer: delegate as Any,
          name: UIApplication.didBecomeActiveNotification,
          selector: #selector(ApplicationDelegate.applicationDidBecomeActive(_:)),
          object: nil
        )
      ),
      "Should start observing application foregrounding upon initialization"
    )
    XCTAssertTrue(
      center.capturedAddObserverInvocations.contains(
        TestNotificationCenter.ObserverEvidence(
          observer: delegate as Any,
          name: UIApplication.willResignActiveNotification,
          selector: #selector(ApplicationDelegate.applicationWillResignActive(_:)),
          object: nil
        )
      ),
      "Should start observing application resignation upon initializtion"
    )
  }

  func testInitializingSdkSetsSessionInformation() {
    delegate.initializeSDK(
      launchOptions: [
        UIApplication.LaunchOptionsKey.sourceApplication: name,
        .url: SampleURLs.valid
      ]
    )

    XCTAssertEqual(
      appEvents.capturedSetSourceApplication,
      name,
      "Should set the source application based on the launch options"
    )
    XCTAssertEqual(
      appEvents.capturedSetSourceApplicationURL,
      SampleURLs.valid,
      "Should set the source application url based on the launch options"
    )
  }

  func testInitializingSdkRegistersForSessionUpdates() {
    delegate.initializeSDK(launchOptions: [:])

    XCTAssertTrue(
      appEvents.wasRegisterAutoResetSourceApplicationCalled,
      "Should have the analytics session register to auto reset the source application"
    )
  }

  // MARK: - Configuring Dependencies

  // TEMP: added to configurator tests
  func testInitializingConfiguresError() {
    SDKError.reset()
    XCTAssertNil(
      SDKError.errorReporter,
      "Should not have an error reporter by default"
    )
    delegate.initializeSDK(launchOptions: [:])

    XCTAssertEqual(
      SDKError.errorReporter as? ErrorReporter,
      ErrorReporter.shared
    )
  }

  func testInitializingConfiguresSuggestedEventsIndexer() throws {
    ModelManager.reset()
    delegate.initializeSDK(launchOptions: [:])

    let indexer = try XCTUnwrap(
      ModelManager.shared.suggestedEventsIndexer as? SuggestedEventsIndexer
    )

    XCTAssertTrue(
      indexer.graphRequestFactory is GraphRequestFactory,
      "Should configure with a request provider of the expected type"
    )
    XCTAssertTrue(
      indexer.serverConfigurationProvider is ServerConfigurationManager,
      "Should configure with a server configuration manager of the expected type"
    )
    XCTAssertTrue(
      indexer.swizzler is Swizzler.Type,
      "Should configure with a swizzler of the expected type"
    )
    XCTAssertTrue(
      indexer.settings is Settings,
      "Should configure with a settings of the expected type"
    )
    XCTAssertTrue(
      indexer.eventLogger === AppEvents.shared,
      "Should configure with the expected event logger"
    )
    XCTAssertTrue(
      indexer.eventProcessor is ModelManager,
      "Should have an event processor of the expected type"
    )
  }

  // TEMP: added to configurator tests
  func testInitializingConfiguresModelManager() {
    ModelManager.reset()
    XCTAssertNil(ModelManager.shared.featureChecker, "Should not have a feature checker by default")
    XCTAssertNil(ModelManager.shared.graphRequestFactory, "Should not have a request factory by default")
    XCTAssertNil(ModelManager.shared.fileManager, "Should not have a file manager by default")
    XCTAssertNil(ModelManager.shared.store, "Should not have a data store by default")
    XCTAssertNil(ModelManager.shared.settings, "Should not have a settings by default")
    XCTAssertNil(ModelManager.shared.dataExtractor, "Should not have a data extractor by default")
    XCTAssertNil(ModelManager.shared.gateKeeperManager, "Should not have a gate keeper manager by default")
    XCTAssertNil(ModelManager.shared.suggestedEventsIndexer, "Should not have a suggested events indexer by default")

    delegate.initializeSDK(launchOptions: [:])

    XCTAssertEqual(
      ModelManager.shared.featureChecker as? FeatureManager,
      FeatureManager.shared,
      "Should configure with the expected concrete feature checker"
    )
    XCTAssertTrue(
      ModelManager.shared.graphRequestFactory is GraphRequestFactory,
      "Should configure with a request factory of the expected type"
    )
    XCTAssertEqual(
      ModelManager.shared.fileManager as? FileManager,
      FileManager.default,
      "Should configure with the expected concrete file manager"
    )
    XCTAssertEqual(
      ModelManager.shared.store as? UserDefaults,
      UserDefaults.standard,
      "Should configure with the expected concrete data store"
    )
    XCTAssertEqual(
      ModelManager.shared.settings as? Settings,
      Settings.shared,
      "Should configure with the expected concrete settings"
    )
    XCTAssertTrue(
      ModelManager.shared.dataExtractor is NSData.Type,
      "Should configure with the expected concrete data extractor"
    )
    XCTAssertTrue(
      ModelManager.shared.gateKeeperManager === GateKeeperManager.self,
      "Should configure with the expected concrete gatekeeper manager"
    )
  }

  // TEMP: added to configurator tests
  func testInitializingConfiguresGraphRequest() {
    GraphRequest.resetClassDependencies()
    delegate.initializeSDK(launchOptions: [:])

    let request = GraphRequest(graphPath: name)
    XCTAssertTrue(
      request.graphRequestConnectionFactory is GraphRequestConnectionFactory,
      "Should configure the graph request with a connection provider to use in creating new instances"
    )
    XCTAssertTrue(
      GraphRequest.accessTokenProvider === AccessToken.self,
      "Should configure the graph request type with the expected concrete token string provider"
    )
  }

  // TEMP: added to configurator tests
  func testInitializingConfiguresFeatureManager() {
    FeatureManager.reset()
    delegate.initializeSDK(launchOptions: [:])

    XCTAssertTrue(
      FeatureManager.shared.gateKeeperManager === GateKeeperManager.self,
      "Should configure with the expected concrete gatekeeper manager"
    )
    XCTAssertTrue(
      FeatureManager.shared.settings === Settings.shared,
      "Should configure with the expected concrete settings"
    )
    XCTAssertTrue(
      FeatureManager.shared.store === UserDefaults.standard,
      "Should configure with the expected concrete data store"
    )
  }

  // TEMP: added to configurator tests -- need to check same feature checker
  // and settings for crash observer
  func testInitializingConfiguresInstrumentManager() throws {
    InstrumentManager.reset()
    delegate.initializeSDK(launchOptions: [:])

    let crashObserver = try XCTUnwrap(
      InstrumentManager.shared.crashObserver as? CrashObserver,
      "Should configure with a crash observer"
    )

    XCTAssertTrue(
      crashObserver.featureChecker === InstrumentManager.shared.featureChecker,
      "Should use the same feature checker for the crash observer and the instrument manager"
    )
    XCTAssertTrue(
      crashObserver.settings === InstrumentManager.shared.settings,
      "Should use the same settings for the crash observer and the instrument manager"
    )
    XCTAssertTrue(
      InstrumentManager.shared.featureChecker is FeatureManager,
      "Should configure with the expected feature checker"
    )
    XCTAssertTrue(
      InstrumentManager.shared.settings === Settings.shared,
      "Should configure with the shared settings instance"
    )
    XCTAssertTrue(
      InstrumentManager.shared.errorReporter === ErrorReporter.shared,
      "Should configure with the shared error reporter instance"
    )
    XCTAssertTrue(
      InstrumentManager.shared.crashHandler === CrashHandler.shared,
      "Should configure with the shared Crash Handler instance"
    )
  }

  // TEMP: added to configurator tests
  func testInitializingConfiguresAppLinkUtility() {
    AppLinkUtility.reset()
    delegate.initializeSDK()

    XCTAssertTrue(
      AppLinkUtility.graphRequestFactory is GraphRequestFactory,
      "Should configure with the expected graph request factory"
    )
    XCTAssertTrue(
      AppLinkUtility.infoDictionaryProvider === Bundle.main,
      "Should configure with the expected info dictionary provider"
    )
    XCTAssertTrue(
      AppLinkUtility.settings === Settings.shared,
      "Should configure with the expected settings"
    )
    XCTAssertTrue(
      AppLinkUtility.appEventsConfigurationProvider === AppEventsConfigurationManager.shared,
      "Should configure with the expected app events configuration manager"
    )
    XCTAssertTrue(
      AppLinkUtility.advertiserIDProvider === AppEventsUtility.shared,
      "Should configure with the expected advertiser id provider"
    )
    XCTAssertTrue(
      AppLinkUtility.appEventsDropDeterminer === AppEventsUtility.shared,
      "Should configure with the expected app events drop determiner"
    )
    XCTAssertTrue(
      AppLinkUtility.appEventParametersExtractor === AppEventsUtility.shared,
      "Should configure with the expected app events parameter extractor"
    )
    XCTAssertTrue(
      AppLinkUtility.appLinkURLFactory is AppLinkURLFactory,
      "Should configure with the expected app link URL factory"
    )
    XCTAssertTrue(
      AppLinkUtility.userIDProvider === AppEvents.shared,
      "Should configure with the expected user id provider"
    )
    XCTAssertTrue(
      AppLinkUtility.userDataStore is UserDataStore,
      "Should configure with the expected user data store"
    )
  }

  func testInitializingCreatesPaymentObserver() throws {
    let observer = try XCTUnwrap(
      ApplicationDelegate.shared.paymentObserver as? PaymentObserver
    )

    XCTAssertEqual(
      observer.paymentQueue,
      SKPaymentQueue.default(),
      "Should create the shared instance with the expected concrete payment queue"
    )
    XCTAssertTrue(
      observer.requestorFactory is PaymentProductRequestorFactory,
      "Should create the shared instance with the expected concrete payment product requestor factory"
    )
  }

  // TEMP: added to configurator tests
  func testInitializingConfiguresServerConfigurationManager() {
    let manager = ServerConfigurationManager.shared
    manager.reset()
    delegate.initializeSDK()

    XCTAssertTrue(manager.graphRequestFactory is GraphRequestFactory)
    XCTAssertTrue(manager.graphRequestConnectionFactory is GraphRequestConnectionFactory)
  }

  // TEMP: added to configurator tests
  func testInitializingConfiguresAppLinkURL() {
    AppLinkURL.reset()
    XCTAssertNil(AppLinkURL.settings)

    delegate.initializeSDK()

    XCTAssertTrue(
      AppLinkURL.settings === Settings.shared,
      "Should configure with the expected settings"
    )
    XCTAssertTrue(
      AppLinkURL.appLinkFactory is AppLinkFactory,
      "Should configure with the expected app link factory"
    )
    XCTAssertTrue(
      AppLinkURL.appLinkTargetFactory is AppLinkTargetFactory,
      "Should configure with the expected app link target factory"
    )
  }

  // TEMP: added to configurator tests
  func testInitializingSDKConfiguresBridgeAPIRequest() {
    BridgeAPIRequest.resetClassDependencies()
    delegate.initializeSDK()

    XCTAssertTrue(
      BridgeAPIRequest.internalUtility === InternalUtility.shared,
      "Should configure with the expected internal utility"
    )
    XCTAssertTrue(
      BridgeAPIRequest.settings === Settings.shared,
      "Should configure with the expected settings"
    )
  }

  // TEMP: added to configurator tests
  func testInitializingSDKConfiguresAppEventsUtility() {
    AppEventsUtility.reset()
    delegate.initializeSDK()

    XCTAssertTrue(
      AppEventsUtility.shared.appEventsConfigurationProvider === AppEventsConfigurationManager.shared,
      "Should configure with the expected app events configuration provider"
    )
  }

  // TEMP: added to configurator tests
  func testInitializingSDKConfiguresGraphRequestConnection() {
    GraphRequestConnection.resetClassDependencies()
    delegate.initializeSDK()

    XCTAssertTrue(
      GraphRequestConnection.sessionProxyFactory is URLSessionProxyFactory,
      "A graph request connection should have the correct concrete session provider by default"
    )
    XCTAssertTrue(
      GraphRequestConnection.errorConfigurationProvider is ErrorConfigurationProvider,
      "A graph request connection should have the correct error configuration provider by default"
    )
    XCTAssertTrue(
      GraphRequestConnection.piggybackManagerProvider is GraphRequestPiggybackManagerProvider,
      "A graph request connection should have the correct piggyback manager provider by default"
    )
    XCTAssertTrue(
      GraphRequestConnection.settings === Settings.shared,
      "A graph request connection should have the correct settings type by default"
    )
    XCTAssertTrue(
      GraphRequestConnection.graphRequestConnectionFactory is GraphRequestConnectionFactory,
      "A graph request connection should have the correct connection factory by default"
    )
    XCTAssertTrue(
      GraphRequestConnection.eventLogger === AppEvents.shared,
      "A graph request connection should have the correct events logger by default"
    )
    XCTAssertTrue(
      GraphRequestConnection.operatingSystemVersionComparer === ProcessInfo.processInfo,
      "A graph request connection should have the correct operating system version comparer by default"
    )
    XCTAssertTrue(
      GraphRequestConnection.macCatalystDeterminator === ProcessInfo.processInfo,
      "A graph request connection should have the correct Mac Catalyst determinator by default"
    )
    XCTAssertTrue(
      GraphRequestConnection.accessTokenProvider === AccessToken.self,
      "A graph request connection should have the correct access token provider by default"
    )
    XCTAssertTrue(
      GraphRequestConnection.accessTokenSetter === AccessToken.self,
      "A graph request connection should have the correct access token setter by default"
    )
    XCTAssertTrue(
      GraphRequestConnection.errorFactory is ErrorFactory,
      "A graph request connection should have an error factory by default"
    )
    XCTAssertTrue(
      GraphRequestConnection.authenticationTokenProvider === AuthenticationToken.self,
      "A graph request connection should have the correct authentication token provider by default"
    )
  }

  // TEMP: added to configurator tests
  func testInitializingSDKConfiguresAuthenticationStatusUtility() {
    AuthenticationStatusUtility.resetClassDependencies()
    delegate.initializeSDK()

    XCTAssertTrue(
      AuthenticationStatusUtility.profileSetter === Profile.self,
      "Should configure with the expected profile setter"
    )
    XCTAssertTrue(
      AuthenticationStatusUtility.sessionDataTaskProvider === URLSession.shared,
      "Should configure with the expected session data task provider"
    )
    XCTAssertTrue(
      AuthenticationStatusUtility.accessTokenWallet === AccessToken.self,
      "Should configure with the expected access token"
    )
    XCTAssertTrue(
      AuthenticationStatusUtility.authenticationTokenWallet === AuthenticationToken.self,
      "Should configure with the expected authentication token"
    )
  }

  // TEMP: added to configurator tests
  func testInitializingSdkConfiguresInternalUtility() {
    InternalUtility.reset()
    delegate.initializeSDK()

    XCTAssertTrue(
      InternalUtility.shared.infoDictionaryProvider === Bundle.main,
      "Should be configured with the expected concrete info dictionary provider"
    )
    XCTAssertTrue(
      InternalUtility.shared.loggerFactory is LoggerFactory,
      "Should be configured with the expected concrete logger factory"
    )
  }

  func testInitializingSdkConfiguresPaymentProductRequestorFactory() throws {
    let paymentObserver = try XCTUnwrap(ApplicationDelegate.shared.paymentObserver as? PaymentObserver)
    let factory = try XCTUnwrap(paymentObserver.requestorFactory as? PaymentProductRequestorFactory)

    XCTAssertTrue(
      factory.settings === Settings.shared,
      "Should be configured with the expected concrete settings"
    )
    XCTAssertTrue(
      factory.eventLogger === AppEvents.shared,
      "Should be configured with the expected concrete event logger"
    )
    XCTAssertTrue(
      factory.gateKeeperManager is GateKeeperManager.Type,
      "Should be configured with the expected concrete gate keeper manager"
    )
    XCTAssertTrue(
      factory.store === UserDefaults.standard,
      "Should be configured with the expected persistent data store"
    )
    XCTAssertTrue(
      factory.loggerFactory is LoggerFactory,
      "Should be configured with the expected concrete logger factory"
    )
    XCTAssertTrue(
      factory.productsRequestFactory is ProductRequestFactory
    )
    XCTAssertTrue(
      factory.appStoreReceiptProvider is Bundle,
      "Should be configured with the expected concrete app store receipt provider"
    )
  }

  // MARK: - DidFinishLaunching

  func testDidFinishLaunchingLoadsServerConfiguration() {
    delegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

    XCTAssertTrue(
      serverConfigurationProvider.loadServerConfigurationWasCalled,
      "Should load a server configuration on finishing launching the application"
    )
  }

  func testDidFinishLaunchingSetsProfileWithCache() {
    TestProfileProvider.stubbedCachedProfile = profile

    delegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

    XCTAssertEqual(
      TestProfileProvider.current,
      profile,
      "Should set the current profile to the value fetched from the cache"
    )
  }

  func testDidFinishLaunchingSetsProfileWithoutCache() {
    XCTAssertNil(
      TestProfileProvider.stubbedCachedProfile,
      "Setup should nil out the cached profile"
    )

    delegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

    XCTAssertNil(
      TestProfileProvider.current,
      "Should set the current profile to nil when the cache is empty"
    )
  }

  // MARK: - URL Opening

  func testOpeningURLChecksAEMFeatureAvailability() {
    delegate.application(
      UIApplication.shared,
      open: SampleURLs.validApp,
      options: [:]
    )
    XCTAssertTrue(
      featureChecker.capturedFeaturesContains(.AEM),
      "Opening a deep link should check if the AEM feature is enabled"
    )
  }

  // MARK: - Application Observers

  func testDefaultsObservers() {
    XCTAssertEqual(
      delegate.applicationObservers.count,
      0,
      "Should have no observers by default"
    )
  }

  func testAddingNewObserver() {
    delegate.addObserver(observer)

    XCTAssertEqual(
      delegate.applicationObservers.count,
      1,
      "Should be able to add a single observer"
    )
  }

  func testAddingDuplicateObservers() {
    delegate.addObserver(observer)
    delegate.addObserver(observer)

    XCTAssertEqual(
      delegate.applicationObservers.count,
      1,
      "Should only add one instance of a given observer"
    )
  }

  func testRemovingObserver() {
    delegate.addObserver(observer)
    delegate.removeObserver(observer)

    XCTAssertEqual(
      delegate.applicationObservers.count,
      0,
      "Should be able to remove observers that are present in the stored list"
    )
  }

  func testRemovingMissingObserver() {
    delegate.removeObserver(observer)

    XCTAssertEqual(
      delegate.applicationObservers.count,
      0,
      "Should not be able to remove absent observers"
    )
  }

  func testAppNotifyObserversWhenAppWillResignActive() {
    delegate.addObserver(observer)

    let notification = Notification(
      name: UIApplication.willResignActiveNotification,
      object: UIApplication.shared,
      userInfo: nil
    )
    delegate.applicationWillResignActive(notification)

    XCTAssertTrue(
      observer.wasWillResignActiveCalled,
      "Should inform observers when the application will resign active status"
    )
  }
} // swiftlint:disable:this file_length
