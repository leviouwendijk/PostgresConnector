import TestFlows

@main
enum PostgresConnectorTestFlowsMain {
    static func main() async {
        await TestFlowCLI.run(
            suite: PostgresConnectorFlowSuite.self
        )
    }
}
