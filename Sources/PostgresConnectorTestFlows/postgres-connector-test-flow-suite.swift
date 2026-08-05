import TestFlows

enum PostgresConnectorFlowSuite:
    TestFlowRegistry
{
    static let title = "PostgresConnector"

    static let flows: [TestFlow] = [
        transactionFlow,
    ]
}
