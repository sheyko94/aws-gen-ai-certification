package com.example.claims;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.S3Event;
import com.amazonaws.services.lambda.runtime.events.models.s3.S3EventNotification;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.*;
import software.amazon.awssdk.services.bedrockagentruntime.BedrockAgentRuntimeClient;
import software.amazon.awssdk.services.bedrockagentruntime.model.KnowledgeBaseQuery;
import software.amazon.awssdk.services.bedrockagentruntime.model.RetrievalResultContent;
import software.amazon.awssdk.services.bedrockagentruntime.model.RetrieveRequest;
import software.amazon.awssdk.services.bedrockagentruntime.model.RetrieveResponse;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.utils.IoUtils;

import java.io.InputStream;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/**
 * Lambda handler that reacts to S3 object created events, runs a simple Bedrock
 * prompt, and writes a result object back to S3.
 */
@SuppressWarnings("unused")
public record ClaimProcessorHandler(S3Client s3Client,
        BedrockRuntimeClient bedrockClient,
        BedrockAgentRuntimeClient bedrockAgentRuntimeClient) implements RequestHandler<S3Event, String> {

    private static final Logger logger = LoggerFactory.getLogger(ClaimProcessorHandler.class);
    private static final String RESULT_SUFFIX = "_result";
    private static final String MODEL_INFERENCE_ID = "eu.anthropic.claude-sonnet-4-5-20250929-v1:0"; // Inference
                                                                                                     // profile
    private static final Pattern POLICY_ID_PATTERN = Pattern.compile("(POL-[A-Za-z0-9_-]+)");
    private static final String KNOWLEDGE_BASE_ID = resolveKnowledgeBaseId();

    public ClaimProcessorHandler() {
        this(S3Client.create(), BedrockRuntimeClient.create(), BedrockAgentRuntimeClient.create());
    }

    public ClaimProcessorHandler {
        Objects.requireNonNull(s3Client, "s3Client must not be null");
        Objects.requireNonNull(bedrockClient, "bedrockClient must not be null");
        Objects.requireNonNull(bedrockAgentRuntimeClient, "bedrockAgentRuntimeClient must not be null");
    }

    @Override
    public String handleRequest(S3Event event, Context context) {
        List<S3EventNotification.S3EventNotificationRecord> records = event.getRecords();
        if (records == null || records.isEmpty()) {
            logger.warn("No S3 records found in event.");
            return "No records";
        }

        S3EventNotification.S3EventNotificationRecord record = records.get(0);
        String bucket = record.getS3().getBucket().getName();
        String rawKey = record.getS3().getObject().getKey();
        String key = URLDecoder.decode(rawKey.replace('+', ' '), StandardCharsets.UTF_8);
        logger.info("Processing s3://{}/{}", bucket, key);

        if (key.endsWith(RESULT_SUFFIX + ".json")) {
            logger.info("Skipping result object {}", key);
            return "Ignored result object";
        }

        try {
            String document = readObjectAsString(bucket, key);
            String policyContext = retrievePolicyContext(document);
            String prompt = buildPrompt(document, policyContext);
            String modelResponse = invokeModel(prompt);
            String resultKey = buildResultKey(key);
            writeResult(bucket, resultKey, modelResponse);
            logger.info("Wrote result to s3://{}/{}", bucket, resultKey);
            return "OK";
        } catch (Exception e) {
            logger.error("Failed processing s3://{}/{}: {}", bucket, key, e, e);
            throw new RuntimeException(e);
        }
    }

    private String readObjectAsString(String bucket, String key) throws Exception {
        GetObjectRequest request = GetObjectRequest.builder()
                .bucket(bucket)
                .key(key)
                .build();

        try (InputStream is = s3Client.getObject(request)) {
            return IoUtils.toUtf8String(is);
        }
    }

    private String buildPrompt(String document, String policyContext) {
        return "You are an insurance claim assistant. " +
                "Derive policy context directly from the claim document (deductibles, limits, exclusions, coverage). " +
                "Do not assume any policy details that are not explicitly present in the document. " +
                "If policy details are missing, return \"unknown\" for that field.\n\n" +
                "Policy information:\n" + policyContext + "\n\n" +
                "Claim document:\n" + document + "\n\n" +
                "Respond with strict JSON only (no code fences, no extra text) containing fields: " +
                "policy_context (summary of coverage details you found), " +
                "summary (succinct claim overview), " +
                "key_entities (list), " +
                "coverage_notes (how policy applies to the claim)." +
                "Be as brief as possible without missing critical details but removing any unnecessary tokens from response to save costs";
    }

    private String invokeModel(String prompt) {
        ConverseRequest request = ConverseRequest.builder()
                .modelId(MODEL_INFERENCE_ID)
                .messages(Message.builder()
                        .role("user")
                        .content(ContentBlock.builder().text(prompt).build())
                        .build())
                .inferenceConfig(InferenceConfiguration.builder()
                        .maxTokens(2048)
                        .temperature(0.2F)
                        .build())
                .build();

        ConverseResponse response = bedrockClient.converse(request);
        return extractText(response);
    }

    private void writeResult(String bucket, String key, String content) {
        PutObjectRequest putRequest = PutObjectRequest.builder()
                .bucket(bucket)
                .key(key)
                .contentType("application/json")
                .build();

        s3Client.putObject(putRequest, RequestBody.fromString(content));
    }

    private String escapeJson(String input) {
        return input.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n");
    }

    private String extractText(ConverseResponse response) {
        return Optional.ofNullable(response)
                .map(ConverseResponse::output)
                .map(ConverseOutput::message)
                .map(Message::content)
                .orElse(List.<ContentBlock>of())
                .stream()
                .map(ContentBlock::text)
                .filter(Objects::nonNull)
                .collect(Collectors.joining());
    }

    private String retrievePolicyContext(String document) {
        String policyId = extractPolicyId(document);
        if (policyId == null) {
            return "Policy ID not found in document.";
        }

        RetrieveResponse resp = bedrockAgentRuntimeClient.retrieve(RetrieveRequest.builder()
                .knowledgeBaseId(KNOWLEDGE_BASE_ID)
                .retrievalQuery(KnowledgeBaseQuery.builder().text(policyId).build())
                .build());

        if (resp == null || resp.retrievalResults() == null || resp.retrievalResults().isEmpty()) {
            return "No policy details found for policy ID " + policyId;
        }

        StringBuilder sb = new StringBuilder();
        resp.retrievalResults().forEach(result -> {
            RetrievalResultContent content = result.content();
            if (content.text() != null) {
                sb.append(content.text()).append("\n");
            }
        });

        String context = sb.toString().trim();
        return context.isEmpty() ? "No policy details found for policy ID " + policyId : context;
    }

    private String extractPolicyId(String document) {
        Matcher matcher = POLICY_ID_PATTERN.matcher(document);
        if (matcher.find()) {
            return matcher.group(1).trim();
        }
        return null;
    }

    private static String resolveKnowledgeBaseId() {
        String fromEnv = System.getenv("KNOWLEDGE_BASE_ID");
        if (fromEnv != null && !fromEnv.isBlank()) {
            return fromEnv;
        }
        return "kb-demo-id";
    }

    private String buildResultKey(String originalKey) {
        int slashIdx = originalKey.lastIndexOf('/') + 1; // 0 if not found
        int dotIdx = originalKey.lastIndexOf('.');

        // If there's no dot after the last slash, treat as "no extension"
        if (dotIdx < slashIdx) {
            dotIdx = originalKey.length();
        }

        String path = originalKey.substring(0, slashIdx);
        String filename = originalKey.substring(slashIdx, dotIdx);

        return path + filename + RESULT_SUFFIX + ".json";
    }
}
