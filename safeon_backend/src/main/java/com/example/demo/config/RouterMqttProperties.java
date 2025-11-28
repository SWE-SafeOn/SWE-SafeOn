package com.example.demo.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import java.util.List;
import java.util.Map;

@Getter
@Setter
@Component
@ConfigurationProperties(prefix = "mqtt.router")
public class RouterMqttProperties {

    private boolean enabled = false;
    private String brokerUri;
    private String clientId;
    private String username;
    private String password;

    private List<String> subscribeTopics;
    private String deviceTopic;
    private String flowTopic;

    private Map<String, String> publishTopics;
    private String blockTopic;

    private int qos = 1;
    private boolean cleanSession = true;
    private int keepAliveSeconds = 30;

    public boolean isReady() {
        return enabled && StringUtils.hasText(brokerUri) && !getTopics().isEmpty();
    }

    public List<String> getTopics() {
        if (subscribeTopics != null && !subscribeTopics.isEmpty()) {
            return subscribeTopics.stream().filter(StringUtils::hasText).toList();
        }
        return List.of(deviceTopic, flowTopic).stream().filter(StringUtils::hasText).toList();
    }

    public Map<String, String> getPublishTopics() {
        return publishTopics != null ? publishTopics : Map.of();
    }

    public String getBlockTopic() {
        String blockFromMap = getPublishTopics().get("block");
        if (StringUtils.hasText(blockFromMap)) {
            return blockFromMap;
        }
        return blockTopic;
    }

    public String getDeviceTopic() {
        if (StringUtils.hasText(deviceTopic)) {
            return deviceTopic;
        }
        return findInSubscribeTopics("device");
    }

    public String getFlowTopic() {
        if (StringUtils.hasText(flowTopic)) {
            return flowTopic;
        }
        return findInSubscribeTopics("flow");
    }

    private String findInSubscribeTopics(String keyword) {
        if (subscribeTopics == null) {
            return null;
        }
        return subscribeTopics.stream()
                .filter(StringUtils::hasText)
                .filter(t -> t.contains(keyword))
                .findFirst()
                .orElse(null);
    }
}
