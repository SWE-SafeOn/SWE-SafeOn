package com.example.demo.dto.device;

import com.example.demo.domain.Device;
import com.example.demo.domain.UserDevice;
import lombok.Builder;

import java.util.UUID;

@Builder
public record DeviceResponseDto(
        String id,
        String userId,
        String macAddress,
        String name,
        String ip,
        Boolean discovered,
        String createdAt,
        String linkedAt
) {

    public static DeviceResponseDto from(UserDevice userDevice) {
        return from(
                userDevice.getDevice(),
                userDevice.getUser().getUserId(),
                userDevice.getLinkedAt() != null ? userDevice.getLinkedAt().toString() : null
        );
    }

    public static DeviceResponseDto from(Device device, UUID userId) {
        return from(device, userId, null);
    }

    private static DeviceResponseDto from(Device device, UUID userId, String linkedAt) {
        return DeviceResponseDto.builder()
                .id(device.getDeviceId() != null ? device.getDeviceId().toString() : null)
                .userId(userId != null ? userId.toString() : null)
                .macAddress(device.getMacAddress())
                .name(device.getName())
                .ip(device.getIp())
                .discovered(device.getDiscovered())
                .createdAt(device.getCreatedAt() != null ? device.getCreatedAt().toString() : null)
                .linkedAt(linkedAt)
                .build();
    }
}
