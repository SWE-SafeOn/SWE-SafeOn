package com.example.demo.service;

import com.example.demo.domain.Device;
import com.example.demo.domain.PacketMeta;
import com.example.demo.domain.UserDevice;
import com.example.demo.dto.device.DeviceTrafficPointDto;
import com.example.demo.repository.PacketMetaRepository;
import com.example.demo.repository.UserDeviceRepository;
import lombok.Builder;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.Duration;
import java.time.temporal.ChronoUnit;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
@Slf4j
public class DeviceTrafficService {

    private static final Duration TRAFFIC_WINDOW = Duration.ofMinutes(15);
    private static final int MAX_POINTS = 300; // guardrail for excessive rows
    private static final Pageable PAGE_LIMIT =
            PageRequest.of(0, MAX_POINTS, Sort.by("startTime").ascending());
    private final PacketMetaRepository packetMetaRepository;
    private final UserDeviceRepository userDeviceRepository;

    @Transactional(readOnly = true)
    public DeviceTrafficSnapshot getRecentSnapshot(UUID deviceId, UUID userId) {
        UserDevice userDevice = userDeviceRepository.getByDeviceAndUser(deviceId, userId);
        Device device = userDevice.getDevice();

        if (device == null || !StringUtils.hasText(device.getIp())) {
            throw new IllegalStateException("디바이스 IP 정보가 없어 트래픽을 조회할 수 없습니다.");
        }

        OffsetDateTime windowStart = OffsetDateTime.now(ZoneOffset.UTC).minus(TRAFFIC_WINDOW);
        List<DeviceTrafficPointDto> points = loadBucketed(device.getIp(), windowStart);

        return DeviceTrafficSnapshot.builder()
                .deviceId(device.getDeviceId())
                .deviceIp(device.getIp())
                .windowStart(windowStart)
                .points(points)
                .build();
    }

    @Transactional(readOnly = true)
    public List<DeviceTrafficPointDto> getSince(String deviceIp, OffsetDateTime since) {
        OffsetDateTime cutoff = OffsetDateTime.now(ZoneOffset.UTC).minus(TRAFFIC_WINDOW);
        OffsetDateTime effectiveSince = since != null && since.isAfter(cutoff) ? since : cutoff;

        return loadBucketed(deviceIp, effectiveSince);
    }

    @Builder
    public record DeviceTrafficSnapshot(
            UUID deviceId,
            String deviceIp,
            OffsetDateTime windowStart,
            List<DeviceTrafficPointDto> points
    ) {
    }

    private List<DeviceTrafficPointDto> loadBucketed(String ip, OffsetDateTime since) {
        try {
            List<DeviceTrafficPointDto> bucketed = packetMetaRepository
                    .findBucketedTraffic(ip, since)
                    .stream()
                    .map(bucket -> DeviceTrafficPointDto.builder()
                            .timestamp(bucket.getBucket())
                            .pps(bucket.getPpsSum())
                            .bps(bucket.getBpsSum())
                            .build())
                    .toList();
            if (!bucketed.isEmpty()) {
                return bucketed;
            }
        } catch (Exception ex) {
            log.warn("버킷 단위 트래픽 조회에 실패했습니다. raw 데이터로 대체합니다. ip={}, since={}", ip, since, ex);
        }

        List<PacketMeta> raw = packetMetaRepository.findRecentByIp(ip, since, PAGE_LIMIT);
        return bucketRawPoints(raw);
    }

    private List<DeviceTrafficPointDto> bucketRawPoints(List<PacketMeta> metas) {
        if (metas == null || metas.isEmpty()) {
            return List.of();
        }

        LinkedHashMap<OffsetDateTime, double[]> buckets = new LinkedHashMap<>();
        for (PacketMeta meta : metas) {
            OffsetDateTime ts = meta.getStartTime();
            if (ts == null) {
                ts = meta.getEndTime();
            }
            if (ts == null) {
                continue;
            }
            OffsetDateTime bucketKey = ts.truncatedTo(ChronoUnit.SECONDS);
            double[] acc = buckets.computeIfAbsent(bucketKey, k -> new double[]{0d, 0d});
            acc[0] += meta.getPps() != null ? meta.getPps() : 0d;
            acc[1] += meta.getBps() != null ? meta.getBps() : 0d;
        }

        return buckets.entrySet().stream()
                .sorted(Comparator.comparing(java.util.Map.Entry::getKey))
                .map(entry -> DeviceTrafficPointDto.builder()
                        .timestamp(entry.getKey())
                        .pps(entry.getValue()[0])
                        .bps(entry.getValue()[1])
                        .build())
                .toList();
    }
}
