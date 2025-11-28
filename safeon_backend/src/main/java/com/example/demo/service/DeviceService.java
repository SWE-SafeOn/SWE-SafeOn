package com.example.demo.service;

import com.example.demo.domain.Device;
import com.example.demo.domain.User;
import com.example.demo.domain.UserDevice;
import com.example.demo.dto.device.DeviceDiscoveryRequestDto;
import com.example.demo.dto.device.DeviceBlockRequestDto;
import com.example.demo.dto.device.DeviceResponseDto;
import com.example.demo.config.MqttProperties;
import com.example.demo.mqtt.MqttClientService;
import com.example.demo.repository.DeviceRepository;
import com.example.demo.repository.UserDeviceRepository;
import com.example.demo.repository.UserRepository;
import com.example.demo.util.UuidParser;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
@Slf4j
public class DeviceService {

    private final DeviceRepository deviceRepository;
    private final UserRepository userRepository;
    private final UserDeviceRepository userDeviceRepository;
    private final MqttClientService mqttClientService;
    private final MqttProperties mqttProperties;
    private final ObjectMapper objectMapper;

    @Transactional
    public void deleteDevice(String deviceId, UUID userId) {
        UUID deviceUuid = UuidParser.parseUUID(deviceId);
        Device device = deviceRepository.getByDeviceId(deviceUuid);

        if (Boolean.FALSE.equals(device.getDiscovered())) {
            userDeviceRepository.findAllByDeviceDeviceId(device.getDeviceId())
                    .forEach(userDeviceRepository::delete);
            deviceRepository.delete(device);
            return;
        }

        UserDevice userDevice = getUserDevice(deviceId, userId);
        userDeviceRepository.findAllByDeviceDeviceId(device.getDeviceId())
                .forEach(userDeviceRepository::delete);
        deviceRepository.delete(device);
    }

    @Transactional(readOnly = true)
    public DeviceResponseDto getDevice(String deviceId, UUID userId) {
        UserDevice userDevice = getUserDevice(deviceId, userId);
        return DeviceResponseDto.from(userDevice.getDevice(), userDevice.getUser().getUserId());
    }

    @Transactional(readOnly = true)
    public List<DeviceResponseDto> getDevices(UUID userId) {
        return userDeviceRepository.findAllByUserUserId(userId)
                .stream()
                .map(DeviceResponseDto::from)
                .toList();
    }

    @Transactional(readOnly = true)
    public List<DeviceResponseDto> getDevicesByStatus(UUID userId, String status) {
        return userDeviceRepository.findAllByUserUserIdAndDeviceDiscoveredAndDeviceStatus(userId, true, status)
                .stream()
                .map(DeviceResponseDto::from)
                .toList();
    }

    @Transactional(readOnly = true)
    public List<DeviceResponseDto> getDevicesByDiscovered(boolean discovered) {
        // Discovery 목록 조회 시 현재 연결된(connect) 디바이스만 노출
        return deviceRepository.findAllByDiscoveredAndStatus(discovered, "connect")
                .stream()
                .map(device -> DeviceResponseDto.from(device, null))
                .toList();
    }

    @Transactional
    public DeviceResponseDto createDiscoveredDevice(DeviceDiscoveryRequestDto request) {
        String status = request.getStatus() != null ? request.getStatus() : "connect";
        Device device = Device.create(
                request.getMacAddress(),
                request.getName(),
                request.getIp(),
                false,
                OffsetDateTime.now(),
                status
        );
        Device saved = deviceRepository.save(device);
        return DeviceResponseDto.from(saved, null);
    }

    @Transactional
    public DeviceResponseDto claimDevice(String deviceId, UUID userId) {
        UUID deviceUuid = UuidParser.parseUUID(deviceId);
        Device device = deviceRepository.getByDeviceId(deviceUuid);
        if (Boolean.TRUE.equals(device.getDiscovered())) {
            throw new IllegalStateException("이미 등록된 디바이스입니다: " + deviceId);
        }

        User user = getUser(userId);
        device.updateDiscovered(true);

        userDeviceRepository.findByDeviceDeviceIdAndUserUserId(deviceUuid, userId)
                .orElseGet(() -> userDeviceRepository.save(
                        UserDevice.create(user, device, null, OffsetDateTime.now())
                ));

        return DeviceResponseDto.from(device, userId);
    }

    @Transactional
    public void blockDevice(UUID userId, DeviceBlockRequestDto request) {
        String deviceId = request.getDeviceId();
        UserDevice userDevice = getUserDevice(deviceId, userId);
        Device device = userDevice.getDevice();

        String blockTopic = mqttProperties.getBlockTopic();
        if (!StringUtils.hasText(blockTopic)) {
            throw new IllegalStateException("MQTT block 토픽이 설정되지 않았습니다.");
        }

        BlockDevicePayload payload = new BlockDevicePayload(
                request.getMacAddress(),
                resolveIp(request, device),
                resolveName(request, device)
        );

        try {
            String json = objectMapper.writeValueAsString(payload);
            mqttClientService.publish(blockTopic, json);
        } catch (JsonProcessingException e) {
            log.error("기기 차단 payload 직렬화 실패. deviceId={}", deviceId, e);
            throw new IllegalStateException("기기 차단 요청 생성에 실패했습니다.");
        }
    }

    private String resolveIp(DeviceBlockRequestDto request, Device device) {
        if (StringUtils.hasText(request.getIp())) {
            return request.getIp();
        }
        return device.getIp();
    }

    private String resolveName(DeviceBlockRequestDto request, Device device) {
        if (StringUtils.hasText(request.getName())) {
            return request.getName();
        }
        return device.getName();
    }

    private record BlockDevicePayload(
            String macAddress,
            String ip,
            String name
    ) {}

    private UserDevice getUserDevice(String deviceId, UUID userId) {
        UUID deviceUuid = UuidParser.parseUUID(deviceId);
        UserDevice userDevice = userDeviceRepository.getByDeviceAndUser(deviceUuid, userId);
        userDevice.ensureOwner(userId);
        return userDevice;
    }

    private User getUser(UUID userId) {
        return userRepository.getById(userId);
    }
}
