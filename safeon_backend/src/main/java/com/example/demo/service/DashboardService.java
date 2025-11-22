package com.example.demo.service;

import com.example.demo.domain.UserAlert;
import com.example.demo.dto.alert.AlertResponseDto;
import com.example.demo.dto.dashboard.DashboardDeviceDto;
import com.example.demo.dto.dashboard.DashboardDeviceListResponseDto;
import com.example.demo.dto.dashboard.DashboardOverviewDto;
import com.example.demo.dto.dashboard.RecentAlertListResponseDto;
import com.example.demo.repository.UserAlertRepository;
import com.example.demo.repository.UserDeviceRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.time.Duration;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.CopyOnWriteArrayList;

@Service
@RequiredArgsConstructor
public class DashboardService {

    private static final long STREAM_TIMEOUT_MILLIS = Duration.ofMinutes(5).toMillis();

    private final UserDeviceRepository userDeviceRepository;
    private final UserAlertRepository userAlertRepository;
    private final ConcurrentMap<UUID, List<SseEmitter>> emitters = new ConcurrentHashMap<>();

    @Transactional(readOnly = true)
    public DashboardOverviewDto getOverview(UUID userId) {
        long totalDevices = userDeviceRepository.countByUserUserId(userId);
        long onlineDevices = totalDevices;
        long alertCount = userAlertRepository.countByUserUserId(userId);
        UserAlert lastAlert = userAlertRepository
                .findFirstByUserUserIdOrderByNotifiedAtDesc(userId)
                .orElse(null);

        return new DashboardOverviewDto(
                (int) totalDevices,
                (int) onlineDevices,
                alertCount,
                lastAlert != null && lastAlert.getNotifiedAt() != null
                        ? lastAlert.getNotifiedAt().toString()
                        : null
        );
    }

    @Transactional(readOnly = true)
    public DashboardDeviceListResponseDto getDevices(UUID userId) {
        List<DashboardDeviceDto> devices = userDeviceRepository
                .findAllByUserUserId(userId)
                .stream()
                .map(DashboardDeviceDto::from)
                .toList();
        return new DashboardDeviceListResponseDto(devices);
    }

    @Transactional(readOnly = true)
    public RecentAlertListResponseDto getRecentAlerts(UUID userId, Integer limit) {
        int size = limit == null || limit <= 0 ? 10 : limit;
        List<AlertResponseDto> alerts = userAlertRepository
                .findByUserUserIdOrderByNotifiedAtDesc(userId)
                .stream()
                .limit(size)
                .map(AlertResponseDto::from)
                .toList();
        return new RecentAlertListResponseDto(alerts);
    }

    public SseEmitter stream(UUID userId) {
        SseEmitter emitter = new SseEmitter(STREAM_TIMEOUT_MILLIS);
        emitters.compute(userId, (key, list) -> {
            List<SseEmitter> updated = list != null ? list : new CopyOnWriteArrayList<>();
            updated.add(emitter);
            return updated;
        });

        Runnable removeCallback = () -> removeEmitter(userId, emitter);
        emitter.onCompletion(removeCallback);
        emitter.onTimeout(removeCallback);
        emitter.onError(ex -> removeCallback.run());

        return emitter;
    }

    public void sendAlertToUser(UserAlert alert) {
        if (alert.getUser() == null || alert.getUser().getUserId() == null) {
            return;
        }
        UUID userId = alert.getUser().getUserId();
        alert.ensureUser(userId);
        List<SseEmitter> emitterList = emitters.get(userId);
        if (emitterList == null || emitterList.isEmpty()) {
            return;
        }

        emitterList.forEach(emitter -> {
            try {
                emitter.send(
                        SseEmitter.event()
                                .name("alert")
                                .data(AlertResponseDto.from(alert))
                );
            } catch (Exception ex) {
                removeEmitter(userId, emitter);
                emitter.completeWithError(ex);
            }
        });
    }

    private void removeEmitter(UUID userId, SseEmitter emitter) {
        emitters.computeIfPresent(userId, (key, list) -> {
            list.remove(emitter);
            return list.isEmpty() ? null : list;
        });
    }
}
