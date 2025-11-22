package com.example.demo.controller;

import com.example.demo.dto.ApiResponseDto;
import com.example.demo.dto.user.UserResponseDto;
import com.example.demo.dto.user.UserUpdateRequestDto;
import com.example.demo.security.AuthenticatedUser;
import com.example.demo.service.MyPageService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequiredArgsConstructor
@RequestMapping("/mypage")
public class MyPageController {

    private final MyPageService myPageService;

    @GetMapping
    public ResponseEntity<ApiResponseDto<UserResponseDto>> getProfile(
            @AuthenticationPrincipal AuthenticatedUser currentUser
    ) {
        UserResponseDto profile = myPageService.getProfile(currentUser.userId());
        return ResponseEntity.ok(ApiResponseDto.ok(profile));
    }

    @PatchMapping
    public ResponseEntity<ApiResponseDto<UserResponseDto>> updateProfile(
            @AuthenticationPrincipal AuthenticatedUser currentUser,
            @Valid @RequestBody UserUpdateRequestDto request
    ) {
        UserResponseDto updated = myPageService.updateProfile(request, currentUser.userId());
        return ResponseEntity.ok(ApiResponseDto.ok(updated));
    }
}
