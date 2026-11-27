# Private Standard File Search troubleshooting

Use this for a Microsoft Foundry Standard agent with bring-your-own Storage, Cosmos DB, and Azure AI Search when a private deployment cannot upload, index, retrieve, or cite an uploaded file. Verify the live agent/runtime variant and its supported configuration before applying this procedure.

## Establish the failing stage

1. Read the deployed project endpoint and model deployment name. From an authorized runner with a route to the private endpoints, verify that the normal HTTPS names resolve to the approved private endpoint NIC addresses. Use an authorized Entra test principal. Check model inference first and keep the runner's identity separate from Foundry account, project, and agent identities. Where isolation is part of acceptance, run an authenticated negative control from outside the approved network and record the expected network denial.
2. Upload a small synthetic file with a unique phrase using the project's Files API. This exercises the Foundry upload path to its backing storage. Direct Blob upload and a portal container listing exercise different callers and operations. If the workload uses another SDK or API version, use its equivalent upload operation.
3. Attach the uploaded file to a test vector store, poll until indexing completes or returns a terminal error, and query the vector store for the unique phrase.
4. Invoke the agent with that store attached. Require the expected phrase and a citation whose file ID matches the upload. Record the first failing stage, UTC timestamp, HTTP status, service error and request or operation IDs. Remove synthetic test artifacts, and report cleanup failures. Reuse a checked-in smoke harness when the repository already has one.

| First failing stage | Inspect |
| --- | --- |
| Private control inference | Exact DNS and route, project endpoint, Entra tenant and token audience, caller's project access, and model deployment availability. |
| File upload with Blob or Asset Store 403 | The Blob operation, actual service principal and effective role scope, and the backend network path. Follow the correlation procedure below. |
| Indexing or direct vector retrieval | The indexing error, intended vector store and file IDs, effective Standard connections and applicable account/project capability hosts, Search endpoint, permissions, and availability. Check Cosmos DB when conversation or agent state fails. |
| Agent answer or citation | Confirm the agent's tool call and attached store. For HTTP 429 inspect effective token and request limits, remaining quota headers and traces. A prompt-only call can fit a deployment that cannot handle a grounded request. Change capacity only as needed for the workload and verify the full test again. |

## Correlate an upload 403

1. Check that Blob write diagnostics are routed to an accessible Log Analytics workspace. If diagnostics are absent, use an authorized configuration change to enable the Blob service's `StorageWrite` category, reproduce once, and restore the prior setting when the diagnostic session ends. Capture Foundry, Dataset and Asset Store IDs when available. An outer client error can contain an inner Asset Store 403 on `temporaryDataReference/createOrGet`.
2. Query the Blob service for the exact storage account and a narrow UTC window around the failure. Correlate IDs where available because different services can issue different IDs. When the IDs differ, correlate timing, account, operation, expected caller and outcome.

```kusto
let uploadTime = datetime(2026-01-01T12:00:00Z); // Replace with the actual UTC upload time.
StorageBlobLogs
| where TimeGenerated between (uploadTime - 2m .. uploadTime + 2m)
| where AccountName =~ "replacewithstorageaccount"
| where tostring(StatusCode) == "403"
| project TimeGenerated, OperationName, StatusCode, StatusText,
          AuthenticationType, RequesterObjectId, CallerIpAddress, ClientRequestId, CorrelationId
| order by TimeGenerated desc
```

3. Resolve the logged object ID to the current principal. Check the applicable data action and role scope, including inherited roles, assignment conditions and propagation. Preserve the distinction between ARM permissions to manage containers and Blob data permissions. Avoid speculative account or agent identity grants when the log identifies a different caller. If there is no matching log, check diagnostics and ingestion delay and retain the service IDs for escalation.
4. If the observed principal has the necessary permissions, check the managed service-to-Storage path separately from the test runner's own Private Link path. Compare effective Storage network policy and the actual NSP associations and modes. In a verified deployment, Foundry and Storage shared an NSP profile in Enforced mode. Upload failed without a subscription inbound rule and the full cited-answer test passed with it enabled and Storage Shared Key and trusted-services bypass disabled. This is evidence for that topology. A subscription rule widens network admission at subscription scope and Blob requests still require data-plane authorization. Verify present provider support and policy, review the exact scope before applying, and change one variable at a time with a known restoration path.
5. After a fix, test the version in infrastructure as code as well as the live experiment. Verify the full cited answer, intended public denial if applicable, and telemetry ingestion. If the backend path remains unverified, use the request IDs and sanitized Blob evidence in a support case.

[Foundry private networking](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/virtual-networks) · [Foundry File Search](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/file-search) · [StorageBlobLogs schema](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/storagebloblogs) · [Storage network security perimeter](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security-perimeter) · [Model quotas and rate limits](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/quota)
