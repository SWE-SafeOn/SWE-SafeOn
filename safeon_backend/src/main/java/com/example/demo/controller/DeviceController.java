package com.example.demo.controller;

import com.example.demo.dto.ApiResponseDto;
import com.example.demo.dto.SimpleMessageResponseDto;
import com.example.demo.dto.device.DeviceDiscoveryRequestDto;
import com.example.demo.dto.device.DeviceResponseDto;
import com.example.demo.security.AuthenticatedUser;
import com.example.demo.service.DeviceService;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequiredArgsConstructor
@RequestMapping("/devices")
@Tag(name = "Device Page")
public class DeviceController {

    private final DeviceService deviceService;

    // 기기 목록 조회
    @GetMapping
    public ResponseEntity<ApiResponseDto<java.util.List<DeviceResponseDto>>> getDevices(
            @AuthenticationPrincipal AuthenticatedUser currentUser
    ) {
        java.util.List<DeviceResponseDto> data = deviceService.getDevices(currentUser.userId());
        return ResponseEntity.ok(ApiResponseDto.ok(data));
    }

    // 발견/미발견 조회하는 기능
    @GetMapping(params = "discovered")
    public ResponseEntity<ApiResponseDto<java.util.List<DeviceResponseDto>>> getDevicesByDiscovered(
            @RequestParam boolean discovered
    ) {
        java.util.List<DeviceResponseDto> data = deviceService.getDevicesByDiscovered(discovered);
        return ResponseEntity.ok(ApiResponseDto.ok(data));
    }

    // 허브 에이전트가 새로운 IoT 기기 발견 시 백엔드에 등록하는 기능
    @PostMapping("/discovery")
    public ResponseEntity<ApiResponseDto<DeviceResponseDto>> createDiscoveredDevice(
            @Valid @RequestBody DeviceDiscoveryRequestDto request
    ) {
        DeviceResponseDto data = deviceService.createDiscoveredDevice(request);
        return ResponseEntity
                .status(HttpStatus.CREATED)
                .body(ApiResponseDto.ok(data));
    }

    // 기기 단일 조회
    @GetMapping("/{deviceId}")
    public ResponseEntity<ApiResponseDto<DeviceResponseDto>> getDevice(
            @AuthenticationPrincipal AuthenticatedUser currentUser,
            @PathVariable String deviceId
    ) {
        DeviceResponseDto data = deviceService.getDevice(deviceId, currentUser.userId());
        return ResponseEntity.ok(ApiResponseDto.ok(data));
    }

    @DeleteMapping("/{deviceId}")
    public ResponseEntity<ApiResponseDto<SimpleMessageResponseDto>> deleteDevice(
            @AuthenticationPrincipal AuthenticatedUser currentUser,
            @PathVariable String deviceId
    ) {
        deviceService.deleteDevice(deviceId, currentUser.userId());
        return ResponseEntity.ok(ApiResponseDto.ok(
                SimpleMessageResponseDto.of("기기 삭제: " + deviceId)
        ));
    }

    @PostMapping("/{deviceId}/claim")
    public ResponseEntity<ApiResponseDto<DeviceResponseDto>> claimDevice(
            @AuthenticationPrincipal AuthenticatedUser currentUser,
            @PathVariable String deviceId
    ) {
        DeviceResponseDto data = deviceService.claimDevice(deviceId, currentUser.userId());
        return ResponseEntity.ok(ApiResponseDto.ok(data));
    }
}
