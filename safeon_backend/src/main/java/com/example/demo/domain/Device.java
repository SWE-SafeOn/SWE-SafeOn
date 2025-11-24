package com.example.demo.domain;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.OffsetDateTime;
import java.util.UUID;
@Entity
@Table(name = "devices")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Device {

    @Id
    @Column(name = "device_id")
    @GeneratedValue(generator = "uuid2")
    private UUID deviceId;

    @Column(name = "ip_address")
    private String ip;

    @Column(name = "discovered")
    private Boolean discovered;

    @Column(name = "created_at")
    private OffsetDateTime createdAt;

    public static Device create(
            String ip,
            Boolean discovered,
            OffsetDateTime createdAt
    ) {
        Device device = new Device();
        device.ip = ip;
        device.discovered = discovered;
        device.createdAt = createdAt;
        return device;
    }

    public void updateDiscovered(Boolean discovered) {
        this.discovered = discovered;
    }
}
