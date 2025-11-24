package com.example.claims;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.S3Event;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import software.amazon.awssdk.services.bedrockagent.BedrockAgentClient;
import software.amazon.awssdk.services.bedrockagent.model.StartIngestionJobRequest;
import software.amazon.awssdk.services.bedrockagent.model.StartIngestionJobResponse;

import java.util.List;
import java.util.Objects;

/**
 * Lambda handler triggered by policy document uploads to kick off a Bedrock Knowledge Base ingestion job.
 */
@SuppressWarnings("unused")
public class PolicySyncHandler implements RequestHandler<S3Event, String> {

    private static final Logger logger = LoggerFactory.getLogger(PolicySyncHandler.class);
    private static final String KB_ID = Objects.requireNonNull(System.getenv("KNOWLEDGE_BASE_ID"),
            "KNOWLEDGE_BASE_ID env var is required");
    private static final String DATA_SOURCE_ID = Objects.requireNonNull(System.getenv("DATA_SOURCE_ID"),
            "DATA_SOURCE_ID env var is required");

    private final BedrockAgentClient agentClient;

    public PolicySyncHandler() {
        this(BedrockAgentClient.create());
    }

    public PolicySyncHandler(BedrockAgentClient agentClient) {
        this.agentClient = Objects.requireNonNull(agentClient, "agentClient must not be null");
    }

    @Override
    public String handleRequest(S3Event input, Context context) {
        List<?> records = input.getRecords();
        if (records == null || records.isEmpty()) {
            logger.info("No records in event; skipping ingestion.");
            return "No records";
        }

        StartIngestionJobRequest request = StartIngestionJobRequest.builder()
                .knowledgeBaseId(KB_ID)
                .dataSourceId(DATA_SOURCE_ID)
                .build();

        StartIngestionJobResponse response = agentClient.startIngestionJob(request);
        logger.info("Started KB ingestion job: {}", response.ingestionJob().ingestionJobId());
        return "Ingestion started: " + response.ingestionJob().ingestionJobId();
    }
}
