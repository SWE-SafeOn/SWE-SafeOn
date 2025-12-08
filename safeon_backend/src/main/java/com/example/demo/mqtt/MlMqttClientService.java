package com.example.demo.mqtt;

import com.example.demo.config.MlMqttProperties;
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
public class MlMqttClientService {

    private final MlMqttProperties properties;
    private final MlResultMqttListener mlResultMqttListener;

    private final AtomicBoolean connected = new AtomicBoolean(false);
    private MqttAsyncClient client;

    @PostConstruct
    public void start() {
        if (!properties.isReady()) {
            log.info("ML MQTT 설정이 완료되지 않았습니다. brokerUri={}, topics={}, enabled={}",
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
            log.warn("ML MQTT 구독 토픽이 비어 있습니다.");
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
                    mlResultMqttListener.onPacketReceived(topic, message.getPayload());
                } catch (Exception ex) {
                    log.warn("ML MQTT 리스너 처리 실패. topic={}", topic, ex);
                }
            };
            IMqttMessageListener[] listenersArray = topics.stream().map(t -> listener).toArray(IMqttMessageListener[]::new);
            client.subscribe(topicArray, qosArray, null, null, listenersArray);

            log.info("ML MQTT 연결 완료. broker={}, topics={}", properties.getBrokerUri(), topics);
        } catch (MqttException e) {
            log.error("ML MQTT 연결/구독에 실패했습니다. broker={}, topics={}", properties.getBrokerUri(), topics, e);
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
        return properties.getClientId() != null ? properties.getClientId() : "backend-ml-" + UUID.randomUUID();
    }

    private void disconnectQuietly() {
        if (client != null && connected.compareAndSet(true, false)) {
            try {
                client.disconnect().waitForCompletion();
                client.close();
            } catch (MqttException e) {
                log.warn("ML MQTT 종료에 실패했습니다.", e);
            }
        }
    }

    public void publish(String topic, String payload) {
        if (!properties.isReady()) {
            log.warn("ML MQTT가 준비되지 않아 publish를 건너뜁니다. topic={}", topic);
            return;
        }
        if (client == null || !connected.get()) {
            log.warn("ML MQTT 클라이언트가 연결되지 않아 publish를 건너뜁니다. topic={}", topic);
            return;
        }

        try {
            MqttMessage message = new MqttMessage(payload.getBytes(StandardCharsets.UTF_8));
            message.setQos(properties.getQos());
            client.publish(topic, message);
            log.info("ML MQTT publish 성공. topic={}", topic);
        } catch (MqttException e) {
            log.error("ML MQTT publish 실패. topic={}", topic, e);
        }
    }
}
