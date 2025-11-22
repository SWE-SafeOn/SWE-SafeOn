package com.example.demo.service;

import com.example.demo.domain.Device;
import com.example.demo.domain.User;
import com.example.demo.domain.UserDevice;
import com.example.demo.dto.device.DeviceDiscoveryRequestDto;
import com.example.demo.dto.device.DeviceResponseDto;
import com.example.demo.repository.DeviceRepository;
import com.example.demo.repository.UserDeviceRepository;
import com.example.demo.repository.UserRepository;
import com.example.demo.util.UuidParser;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class DeviceService {

    private final DeviceRepository deviceRepository;
    private final UserRepository userRepository;
    private final UserDeviceRepository userDeviceRepository;

    @Transactional
    public void deleteDevice(String deviceId, UUID userId) {
        UserDevice userDevice = getUserDevice(deviceId, userId);
        Device device = userDevice.getDevice();
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
    public List<DeviceResponseDto> getDevicesByDiscovered(boolean discovered) {
        return deviceRepository.findAllByDiscovered(discovered)
                .stream()
                .map(device -> DeviceResponseDto.from(device, null))
                .toList();
    }

    @Transactional
    public DeviceResponseDto createDiscoveredDevice(DeviceDiscoveryRequestDto request) {
        Device device = Device.create(
                request.getVendor(),
                request.getIp(),
                request.getMacAddr(),
                false,
                OffsetDateTime.now()
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
                        UserDevice.create(user, device, device.getVendor(), OffsetDateTime.now())
                ));

        return DeviceResponseDto.from(device, userId);
    }

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
