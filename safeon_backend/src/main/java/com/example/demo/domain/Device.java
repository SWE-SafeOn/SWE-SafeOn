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

    @Column(name = "mac_address")
    private String macAddress;

    @Column(name = "name")
    private String name;

    @Column(name = "ip_address")
    private String ip;

    @Column(name = "discovered")
    private Boolean discovered;

    @Column(name = "created_at")
    private OffsetDateTime createdAt;

    @Column(name = "status")
    private String status;

    public static Device create(
            String macAddress,
            String name,
            String ip,
            Boolean discovered,
            OffsetDateTime createdAt,
            String status
    ) {
        Device device = new Device();
        device.macAddress = macAddress;
        device.name = name;
        device.ip = ip;
        device.discovered = discovered;
        device.createdAt = createdAt;
        device.status = status;
        return device;
    }

    public void updateDiscovered(Boolean discovered) {
        this.discovered = discovered;
    }

    public void updateStatus(String status) {
        this.status = status;
    }

    public void updateIp(String ip) {
        this.ip = ip;
    }
}
