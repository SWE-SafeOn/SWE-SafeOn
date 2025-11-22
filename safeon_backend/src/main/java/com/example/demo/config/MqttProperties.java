// package com.example.demo.config;

// import lombok.Getter;
// import lombok.Setter;
// import org.springframework.boot.context.properties.ConfigurationProperties;
// import org.springframework.stereotype.Component;
// import org.springframework.util.StringUtils;

// @Getter
// @Setter
// @Component
// @ConfigurationProperties(prefix = "mqtt")
// public class MqttProperties {

//     /**
//      * MQTT 사용 여부 (환경 준비가 끝나기 전까지 false 유지).
//      */
//     private boolean enabled = false;

//     /**
//      * ex) tcp://localhost:1883 or ssl://broker:8883
//      */
//     private String brokerUri;

//     /**
//      * null 시 랜덤 UUID 기반 client id 사용.
//      */
//     private String clientId;

//     private String username;

//     private String password;

//     /**
//      * 라우터가 패킷을 publish 하는 토픽.
//      */
//     private String subscribeTopic;

//     private int qos = 1;

//     private boolean cleanSession = true;

//     private int keepAliveSeconds = 30;

//     public boolean isReady() {
//         return enabled && StringUtils.hasText(brokerUri) && StringUtils.hasText(subscribeTopic);
//     }
// }
