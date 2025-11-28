package com.example.demo.mqtt;

import com.example.demo.config.MqttProperties;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.eclipse.paho.client.mqttv3.IMqttMessageListener;
import org.eclipse.paho.client.mqttv3.MqttAsyncClient;
import org.eclipse.paho.client.mqttv3.MqttConnectOptions;
import org.eclipse.paho.client.mqttv3.MqttException;
import org.eclipse.paho.client.mqttv3.MqttMessage;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Service;

import java.util.List;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

@Service
@RequiredArgsConstructor
@Slf4j
public class MqttClientService {

    private final MqttProperties properties;
    private final ObjectProvider<MqttPacketListener> packetListeners;

    private final AtomicBoolean connected = new AtomicBoolean(false);
    private MqttAsyncClient client;

    @PostConstruct
    public void start() {
        if (!properties.isReady()) {
            log.info("MQTT 연결되지 않았습니다. brokerUri={}, topics={}, enabled={}",
                    properties.getBrokerUri(), properties.getTopics(), properties.isEnabled());
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
            log.warn("MQTT 토픽이 일치하지 않습니다.");
            return;
        }

        try {
            client = new MqttAsyncClient(properties.getBrokerUri(), resolveClientId());
            client.setCallback(null); // callback 대신 subscribe listener 사용
            client.connect(buildOptions()).waitForCompletion();
            connected.set(true);

            String[] topicArray = topics.toArray(new String[0]);
            int[] qosArray = topics.stream().mapToInt(t -> properties.getQos()).toArray();
            IMqttMessageListener listener = messageListener();
            IMqttMessageListener[] listenersArray = topics.stream().map(t -> listener).toArray(IMqttMessageListener[]::new);
            client.subscribe(topicArray, qosArray, null, null, listenersArray);

            log.info("MQTT 연결됨. broker={}, topics={}", properties.getBrokerUri(), topics);
        } catch (MqttException e) {
            log.error("MQTT connect/subscribe 실패. broker={}, topics={}", properties.getBrokerUri(), topics, e);
        }
    }

    private IMqttMessageListener messageListener() {
        List<MqttPacketListener> listeners = packetListeners.orderedStream().toList();
        return (topic, message) -> {
            byte[] payload = message.getPayload();
            for (MqttPacketListener listener : listeners) {
                try {
                    listener.onPacketReceived(topic, payload);
                } catch (Exception ex) {
                    log.warn("MQTT packet listener 실패. listener={}, topic={}", listener.getClass().getSimpleName(), topic, ex);
                }
            }
        };
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
        return properties.getClientId() != null ? properties.getClientId() : "backend-" + UUID.randomUUID();
    }

    private void disconnectQuietly() {
        if (client != null && connected.compareAndSet(true, false)) {
            try {
                client.disconnect().waitForCompletion();
                client.close();
            } catch (MqttException e) {
                log.warn("MQTT 연결해제 실패", e);
            }
        }
    }

    /**
     * MQTT publish helper for backend-originated events (e.g., device block).
     */
    public void publish(String topic, String payload) {
        if (!properties.isReady()) {
            log.warn("MQTT 설정이 준비되지 않아 publish를 건너뜁니다. topic={}", topic);
            return;
        }
        if (client == null || !connected.get()) {
            log.warn("MQTT 클라이언트가 연결되지 않아 publish를 건너뜁니다. topic={}", topic);
            return;
        }

        try {
            MqttMessage message = new MqttMessage(payload.getBytes(StandardCharsets.UTF_8));
            message.setQos(properties.getQos());
            client.publish(topic, message);
            log.info("MQTT publish 성공. topic={}", topic);
        } catch (MqttException e) {
            log.error("MQTT publish 실패. topic={}", topic, e);
        }
    }
}
