package com.example.demo.controller;

import com.example.demo.dto.ApiResponseDto;
import com.example.demo.dto.alert.AlertResponseDto;
import com.example.demo.security.AuthenticatedUser;
import com.example.demo.service.AlertService;

import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;


@RestController
@RequiredArgsConstructor
@RequestMapping("/alerts")
@Tag(name = "Alerts")
public class AlertController {

    private final AlertService alertService;

    // 모든 로그 조회
    @GetMapping
    public ResponseEntity<ApiResponseDto<List<AlertResponseDto>>> getAlerts(
            @AuthenticationPrincipal AuthenticatedUser currentUser
    ) {
        List<AlertResponseDto> alerts = alertService.getAlerts(currentUser.userId());
        return ResponseEntity.ok(ApiResponseDto.ok(alerts));
    }

    // 로그 상세 조회
    @GetMapping("/{alertId}")
    public ResponseEntity<ApiResponseDto<AlertResponseDto>> getAlert(
            @AuthenticationPrincipal AuthenticatedUser currentUser,
            @PathVariable String alertId
    ) {
        AlertResponseDto alert = alertService.getAlert(alertId, currentUser.userId());
        return ResponseEntity.ok(ApiResponseDto.ok(alert));
    }

    // 로그 확인 여부
    @PostMapping("/{alertId}/ack")
    public ResponseEntity<ApiResponseDto<AlertResponseDto>> acknowledgeAlert(
            @AuthenticationPrincipal AuthenticatedUser currentUser,
            @PathVariable String alertId
    ) {
        AlertResponseDto alert = alertService.acknowledgeAlert(alertId, currentUser.userId());
        return ResponseEntity.ok(ApiResponseDto.ok(alert));
    }
}
