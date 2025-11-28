package com.example.demo.mqtt;

import com.example.demo.config.RouterMqttProperties;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.eclipse.paho.client.mqttv3.IMqttMessageListener;
import org.eclipse.paho.client.mqttv3.MqttAsyncClient;
import org.eclipse.paho.client.mqttv3.MqttConnectOptions;
import org.eclipse.paho.client.mqttv3.MqttException;
import org.eclipse.paho.client.mqttv3.MqttMessage;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

@Service
@RequiredArgsConstructor
@Slf4j
public class RouterMqttClientService {

    private final RouterMqttProperties properties;
    private final RouterMqttPacketListener routerMqttPacketListener;

    private final AtomicBoolean connected = new AtomicBoolean(false);
    private MqttAsyncClient client;

    @PostConstruct
    public void start() {
        if (!properties.isReady()) {
            log.info("Router MQTT not ready. brokerUri={}, topics={}, enabled={}",
                    properties.getBrokerUri(), properties.getTopics(), properties.isReady());
            return;
        }
        connectAndSubscribe();
    }

    @PreDestroy
    public void shutdown() {
        disconnectQuietly();
    }

    private void connectAndSubscribe() {
        List<String> topics = properties.getTopics();
        if (topics.isEmpty()) {
            log.warn("Router MQTT topics empty.");
            return;
        }

        try {
            client = new MqttAsyncClient(properties.getBrokerUri(), resolveClientId());
            client.setCallback(null);
            client.connect(buildOptions()).waitForCompletion();
            connected.set(true);

            String[] topicArray = topics.toArray(new String[0]);
            int[] qosArray = topics.stream().mapToInt(t -> properties.getQos()).toArray();
            IMqttMessageListener listener = (topic, message) -> {
                try {
                    routerMqttPacketListener.onPacketReceived(topic, message.getPayload());
                } catch (Exception ex) {
                    log.warn("Router MQTT listener failed. topic={}", topic, ex);
                }
            };
            IMqttMessageListener[] listenersArray = topics.stream().map(t -> listener).toArray(IMqttMessageListener[]::new);
            client.subscribe(topicArray, qosArray, null, null, listenersArray);

            log.info("Router MQTT connected. broker={}, topics={}", properties.getBrokerUri(), topics);
        } catch (MqttException e) {
            log.error("Router MQTT connect/subscribe failed. broker={}, topics={}", properties.getBrokerUri(), topics, e);
        }
    }

    private MqttConnectOptions buildOptions() {
        MqttConnectOptions options = new MqttConnectOptions();
        options.setCleanSession(properties.isCleanSession());
        options.setKeepAliveInterval(properties.getKeepAliveSeconds());
        if (properties.getUsername() != null) {
            options.setUserName(properties.getUsername());
        }
        if (properties.getPassword() != null) {
            options.setPassword(properties.getPassword().toCharArray());
        }
        return options;
    }

    private String resolveClientId() {
        return properties.getClientId() != null ? properties.getClientId() : "backend-router-" + UUID.randomUUID();
    }

    private void disconnectQuietly() {
        if (client != null && connected.compareAndSet(true, false)) {
            try {
                client.disconnect().waitForCompletion();
                client.close();
            } catch (MqttException e) {
                log.warn("Router MQTT disconnect failed", e);
            }
        }
    }

    public void publish(String topic, String payload) {
        if (!properties.isReady()) {
            log.warn("Router MQTT not ready. skip publish. topic={}", topic);
            return;
        }
        if (client == null || !connected.get()) {
            log.warn("Router MQTT client not connected. skip publish. topic={}", topic);
            return;
        }

        try {
            MqttMessage message = new MqttMessage(payload.getBytes(StandardCharsets.UTF_8));
            message.setQos(properties.getQos());
            client.publish(topic, message);
            log.info("Router MQTT publish success. topic={}", topic);
        } catch (MqttException e) {
            log.error("Router MQTT publish failed. topic={}", topic, e);
        }
    }
}
