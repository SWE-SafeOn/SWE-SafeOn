package com.example.demo.service;

import com.example.demo.domain.Device;
import com.example.demo.domain.UserDevice;
import com.example.demo.dto.device.DeviceTrafficPointDto;
import com.example.demo.repository.PacketMetaRepository;
import com.example.demo.repository.UserDeviceRepository;
import lombok.Builder;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class DeviceTrafficService {

    private static final int MAX_POINTS = 1200; // 1 hour / 3s interval
    private static final Sort START_TIME_ASC = Sort.by(Sort.Direction.ASC, "startTime");

    private final PacketMetaRepository packetMetaRepository;
    private final UserDeviceRepository userDeviceRepository;

    @Transactional(readOnly = true)
    public DeviceTrafficSnapshot getLastHourSnapshot(UUID deviceId, UUID userId) {
        UserDevice userDevice = userDeviceRepository.getByDeviceAndUser(deviceId, userId);
        Device device = userDevice.getDevice();

        if (device == null || !StringUtils.hasText(device.getIp())) {
            throw new IllegalStateException("디바이스 IP 정보가 없어 트래픽을 조회할 수 없습니다.");
        }

        OffsetDateTime windowStart = OffsetDateTime.now(ZoneOffset.UTC).minusHours(1);
        List<DeviceTrafficPointDto> points = packetMetaRepository
                .findRecentByIp(device.getIp(), windowStart, PageRequest.of(0, MAX_POINTS, START_TIME_ASC))
                .stream()
                .map(DeviceTrafficPointDto::from)
                .toList();

        return DeviceTrafficSnapshot.builder()
                .deviceId(device.getDeviceId())
                .deviceIp(device.getIp())
                .windowStart(windowStart)
                .points(points)
                .build();
    }

    @Transactional(readOnly = true)
    public List<DeviceTrafficPointDto> getSince(String deviceIp, OffsetDateTime since) {
        OffsetDateTime cutoff = OffsetDateTime.now(ZoneOffset.UTC).minusHours(1);
        OffsetDateTime effectiveSince = since != null && since.isAfter(cutoff) ? since : cutoff;

        return packetMetaRepository
                .findRecentByIp(deviceIp, effectiveSince, PageRequest.of(0, MAX_POINTS, START_TIME_ASC))
                .stream()
                .map(DeviceTrafficPointDto::from)
                .toList();
    }

    @Builder
    public record DeviceTrafficSnapshot(
            UUID deviceId,
            String deviceIp,
            OffsetDateTime windowStart,
            List<DeviceTrafficPointDto> points
    ) {
    }
}
