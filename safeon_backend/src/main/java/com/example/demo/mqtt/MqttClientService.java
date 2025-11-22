// package com.example.demo.mqtt;

// import com.example.demo.config.MqttProperties;
// import lombok.RequiredArgsConstructor;
// import lombok.extern.slf4j.Slf4j;
// import org.eclipse.paho.client.mqttv3.IMqttMessageListener;
// import org.eclipse.paho.client.mqttv3.MqttAsyncClient;
// import org.eclipse.paho.client.mqttv3.MqttConnectOptions;
// import org.eclipse.paho.client.mqttv3.MqttException;
// import org.springframework.beans.factory.ObjectProvider;
// import org.springframework.stereotype.Service;

// import jakarta.annotation.PostConstruct;
// import jakarta.annotation.PreDestroy;
// import java.util.List;
// import java.util.UUID;
// import java.util.concurrent.atomic.AtomicBoolean;

// @Service
// @RequiredArgsConstructor
// @Slf4j
// public class MqttClientService {

//     private final MqttProperties properties;
//     private final ObjectProvider<MqttPacketListener> packetListeners;

//     private final AtomicBoolean connected = new AtomicBoolean(false);
//     private MqttAsyncClient client;

//     @PostConstruct
//     public void start() {
//         if (!properties.isReady()) {
//             log.info("MQTT disabled or not configured yet. brokerUri={}, topic={}, enabled={}",
//                     properties.getBrokerUri(), properties.getSubscribeTopic(), properties.isEnabled());
//             return;
//         }
//         connectAndSubscribe();
//     }

//     @PreDestroy
//     public void shutdown() {
//         disconnectQuietly();
//     }

//     private void connectAndSubscribe() {
//         try {
//             client = new MqttAsyncClient(properties.getBrokerUri(), resolveClientId());
//             client.setCallback(null); // callback 대신 subscribe listener 사용
//             client.connect(buildOptions()).waitForCompletion();
//             connected.set(true);
//             client.subscribe(properties.getSubscribeTopic(), properties.getQos(), messageListener());
//             log.info("MQTT connected. broker={}, topic={}", properties.getBrokerUri(), properties.getSubscribeTopic());
//         } catch (MqttException e) {
//             log.error("MQTT connect/subscribe failed. broker={}, topic={}", properties.getBrokerUri(), properties.getSubscribeTopic(), e);
//         }
//     }

//     private IMqttMessageListener messageListener() {
//         List<MqttPacketListener> listeners = packetListeners.orderedStream().toList();
//         return (topic, message) -> {
//             byte[] payload = message.getPayload();
//             for (MqttPacketListener listener : listeners) {
//                 try {
//                     listener.onPacketReceived(topic, payload);
//                 } catch (Exception ex) {
//                     log.warn("MQTT packet listener failed. listener={}, topic={}", listener.getClass().getSimpleName(), topic, ex);
//                 }
//             }
//         };
//     }

//     private MqttConnectOptions buildOptions() {
//         MqttConnectOptions options = new MqttConnectOptions();
//         options.setCleanSession(properties.isCleanSession());
//         options.setKeepAliveInterval(properties.getKeepAliveSeconds());
//         if (properties.getUsername() != null) {
//             options.setUserName(properties.getUsername());
//         }
//         if (properties.getPassword() != null) {
//             options.setPassword(properties.getPassword().toCharArray());
//         }
//         return options;
//     }

//     private String resolveClientId() {
//         return properties.getClientId() != null ? properties.getClientId() : "backend-" + UUID.randomUUID();
//     }

//     private void disconnectQuietly() {
//         if (client != null && connected.compareAndSet(true, false)) {
//             try {
//                 client.disconnect().waitForCompletion();
//                 client.close();
//             } catch (MqttException e) {
//                 log.warn("MQTT disconnect failed", e);
//             }
//         }
//     }
// }
