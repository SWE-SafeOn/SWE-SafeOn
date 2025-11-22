package com.example.demo.dto.device;

import com.example.demo.domain.Device;
import com.example.demo.domain.UserDevice;
import lombok.Builder;

import java.util.UUID;

@Builder
public record DeviceResponseDto(
        String id,
        String userId,
        String vendor,
        String ip,
        String macAddr,
        Boolean discovered,
        String createdAt,
        String linkedAt,
        String label
) {

    public static DeviceResponseDto from(UserDevice userDevice) {
        return from(userDevice.getDevice(), userDevice.getUser().getUserId(),
                userDevice.getLinkedAt() != null ? userDevice.getLinkedAt().toString() : null,
                userDevice.getLabel());
    }

    public static DeviceResponseDto from(Device device, UUID userId) {
        return from(device, userId, null, null);
    }

    private static DeviceResponseDto from(Device device, UUID userId, String linkedAt, String label) {
        return DeviceResponseDto.builder()
                .id(device.getDeviceId() != null ? device.getDeviceId().toString() : null)
                .userId(userId != null ? userId.toString() : null)
                .vendor(device.getVendor())
                .ip(device.getIp())
                .macAddr(device.getMacAddr())
                .discovered(device.getDiscovered())
                .createdAt(device.getCreatedAt() != null ? device.getCreatedAt().toString() : null)
                .linkedAt(linkedAt)
                .label(label)
                .build();
    }
}
