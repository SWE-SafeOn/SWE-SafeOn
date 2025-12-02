package com.example.demo.websocket;

import com.example.demo.dto.device.DeviceTrafficPointDto;
import com.example.demo.security.AuthenticatedUser;
import com.example.demo.service.DeviceTrafficService;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.TaskScheduler;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;
import org.springframework.web.util.UriTemplate;

import java.io.IOException;
import java.net.URI;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.atomic.AtomicReference;

@Slf4j
@Component
@RequiredArgsConstructor
public class DeviceTrafficWebSocketHandler extends TextWebSocketHandler {

    private static final Duration PUSH_INTERVAL = Duration.ofSeconds(5);
    private static final UriTemplate URI_TEMPLATE = new UriTemplate("/ws/devices/{deviceId}/traffic");

    private final DeviceTrafficService deviceTrafficService;
    private final TaskScheduler taskScheduler;
    private final ObjectMapper objectMapper;

    private final Map<String, SessionState> sessionStates = new ConcurrentHashMap<>();
    private final Map<String, ScheduledFuture<?>> schedules = new ConcurrentHashMap<>();

    @Override
    public void afterConnectionEstablished(WebSocketSession session) throws Exception {
        AuthenticatedUser user = (AuthenticatedUser) session.getAttributes().get("user");
        if (user == null) {
            session.close(CloseStatus.NOT_ACCEPTABLE.withReason("인증 토큰이 필요합니다."));
            return;
        }

        UUID deviceId = resolveDeviceId(session.getUri());
        if (deviceId == null) {
            session.close(CloseStatus.BAD_DATA.withReason("deviceId가 유효하지 않습니다."));
            return;
        }

        DeviceTrafficService.DeviceTrafficSnapshot snapshot;
        try {
            snapshot = deviceTrafficService.getRecentSnapshot(deviceId, user.userId());
        } catch (Exception ex) {
            log.warn("Failed to prepare traffic snapshot. deviceId={}, userId={}", deviceId, user.userId(), ex);
            session.close(CloseStatus.POLICY_VIOLATION.withReason(ex.getMessage()));
            return;
        }

        OffsetDateTime lastTs = snapshot.points().isEmpty()
                ? snapshot.windowStart()
                : snapshot.points().get(snapshot.points().size() - 1).timestamp();

        SessionState state = new SessionState(
                deviceId,
                snapshot.deviceIp(),
                snapshot.windowStart(),
                new AtomicReference<>(lastTs),
                session
        );
        sessionStates.put(session.getId(), state);

        sendPayload(session, new TrafficMessage(
                "snapshot",
                snapshot.windowStart(),
                snapshot.points(),
                deviceId
        ));

        ScheduledFuture<?> scheduled = taskScheduler.scheduleAtFixedRate(
                () -> pushUpdates(state),
                PUSH_INTERVAL.toMillis()
        );
        schedules.put(session.getId(), scheduled);
    }

    @Override
    public void handleTransportError(WebSocketSession session, Throwable exception) throws Exception {
        log.warn("WebSocket transport error. sessionId={}", session.getId(), exception);
        safeClose(session, CloseStatus.SERVER_ERROR.withReason("데이터 전송 오류가 발생했습니다."));
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) throws Exception {
        cleanup(session.getId());
    }

    private void pushUpdates(SessionState state) {
        WebSocketSession session = state.session();
        if (!session.isOpen()) {
            cleanup(session.getId());
            return;
        }

        try {
            List<DeviceTrafficPointDto> updates = deviceTrafficService.getSince(
                    state.deviceIp(),
                    state.lastSent().get()
            );

            if (updates.isEmpty()) {
                return;
            }

            OffsetDateTime newestTs = updates.get(updates.size() - 1).timestamp();
            state.lastSent().set(newestTs);
            sendPayload(session, new TrafficMessage(
                    "delta",
                    state.windowStart(),
                    updates,
                    state.deviceId()
            ));
        } catch (Exception ex) {
            log.warn("Failed to push traffic updates. deviceId={}, sessionId={}", state.deviceId(), session.getId(), ex);
            safeClose(session, CloseStatus.SERVER_ERROR.withReason("트래픽 데이터 전송에 실패했습니다."));
        }
    }

    private void cleanup(String sessionId) {
        ScheduledFuture<?> future = schedules.remove(sessionId);
        if (future != null) {
            future.cancel(true);
        }
        sessionStates.remove(sessionId);
    }

    private void safeClose(WebSocketSession session, CloseStatus status) {
        cleanup(session.getId());
        if (session.isOpen()) {
            try {
                session.close(status);
            } catch (IOException ignored) {
            }
        }
    }

    private void sendPayload(WebSocketSession session, TrafficMessage payload) {
        if (!session.isOpen()) {
            cleanup(session.getId());
            return;
        }
        try {
            session.sendMessage(new TextMessage(objectMapper.writeValueAsString(payload)));
        } catch (Exception ex) {
            log.warn("Failed to send traffic payload. sessionId={}", session.getId(), ex);
            safeClose(session, CloseStatus.SERVER_ERROR.withReason("데이터 전송 실패"));
        }
    }

    private UUID resolveDeviceId(URI uri) {
        if (uri == null) {
            return null;
        }
        Map<String, String> variables = URI_TEMPLATE.match(uri.getPath());
        String raw = variables.get("deviceId");
        if (!StringUtils.hasText(raw)) {
            return null;
        }
        try {
            return UUID.fromString(raw);
        } catch (IllegalArgumentException ex) {
            return null;
        }
    }

    private record SessionState(
            UUID deviceId,
            String deviceIp,
            OffsetDateTime windowStart,
            AtomicReference<OffsetDateTime> lastSent,
            WebSocketSession session
    ) {
    }

    private record TrafficMessage(
            String type,
            OffsetDateTime windowStart,
            List<DeviceTrafficPointDto> points,
            UUID deviceId
    ) {
    }
}
