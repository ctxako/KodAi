//
//  BenchmarkUploadTests.swift
//  KodAi iOSTests
//
//  On-device benchmark: runs the shared KodaiBenchKit measurement loop against
//  the bundled model on real hardware and uploads to the bench Worker. This is
//  the product-truth counterpart to the macOS `kodai-bench` CLI — same runtime,
//  same prompts, different machine.
//
//  Run it explicitly (token injected at runtime, never stored in source):
//
//    xcodebuild test -scheme "KodAi iOS" \
//      -destination 'platform=iOS,id=<device-id>' \
//      -only-testing:"KodAi iOSTests/BenchmarkUploadTests" \
//      TEST_RUNNER_BENCH_TOKEN=<token> \
//      TEST_RUNNER_BENCH_EXPERIMENT_ID=iphone-baseline-001 \
//      TEST_RUNNER_BENCH_ENDPOINT=https://bench-api.ctxa.ltd
//
//  TEST_RUNNER_-prefixed vars are injected into the test runner process at
//  runtime, so the token touches neither source nor git.
//

import KodaiBenchKit
import KodaiKernel
import KodaiRuntime
import XCTest
@testable import KodAi

final class BenchmarkUploadTests: XCTestCase {

    func testRunOnDeviceAndUpload() async throws {
        let env = ProcessInfo.processInfo.environment

        // Skip in the normal suite — this loads a model and runs several
        // generations. Opt in with a token (the usual path) or BENCH_RUN=1.
        try XCTSkipUnless(
            env["BENCH_TOKEN"] != nil || env["BENCH_RUN"] == "1",
            "Set TEST_RUNNER_BENCH_TOKEN (or BENCH_RUN=1) to run the on-device benchmark."
        )

        let configuration = LocalModelConfiguration.lfm2_5_1_2B_Instruct_Q4_K_M
        let runtime = LocalModelRuntime(
            configuration: configuration,
            modelFileResolver: BundledModelFileResolver()
        )

        let device = DeviceInfo.current
        let experimentId = env["BENCH_EXPERIMENT_ID"] ?? "iphone-baseline-001"
        let modelFileName = configuration.expectedModelFileName
        let modelName = (modelFileName as NSString).deletingPathExtension

        let runs = try await BenchmarkRunner().run(
            runtime: runtime,
            modelName: modelName,
            quant: extractQuant(fromModelName: modelFileName),
            prompts: BenchPrompt.defaultSet,
            experimentId: experimentId,
            device: device,
            knobs: configuration.defaultSamplerKnobs,
            log: { print("[bench] \($0)") }
        )

        XCTAssertEqual(runs.count, BenchPrompt.defaultSet.count, "every prompt should produce a run")
        XCTAssertTrue(runs.contains { $0.tokens_per_sec > 0 }, "at least one prompt should generate tokens")

        // Upload only from a real device with a token. The simulator's Metal
        // numbers are not comparable, so we never pollute the dataset with them.
        guard !DeviceInfo.isSimulator else {
            print("[bench] simulator (device=\(device)) — measured but not uploading")
            return
        }
        guard let token = env["BENCH_TOKEN"] else {
            print("[bench] no token — local-only run on \(device)")
            return
        }
        let endpointString = env["BENCH_ENDPOINT"] ?? "https://bench-api.ctxa.ltd"
        let endpoint = try XCTUnwrap(URL(string: endpointString))

        try await ResultUploader(endpoint: endpoint, token: token).upload(runs)
        print("[bench] uploaded \(runs.count) runs as \(experimentId) on \(device)")
    }
}
