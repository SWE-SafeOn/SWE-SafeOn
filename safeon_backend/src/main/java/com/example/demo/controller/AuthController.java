package com.example.demo.controller;

import com.example.demo.dto.ApiResponseDto;
import com.example.demo.dto.SimpleMessageResponseDto;
import com.example.demo.dto.user.JwtResponseDto;
import com.example.demo.dto.user.LoginRequestDto;
import com.example.demo.dto.user.SignUpRequestDto;
import com.example.demo.service.AuthService;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.AllArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@AllArgsConstructor
@RequestMapping("/auth")
@Tag(name = "User Auth")
public class AuthController {

    private final AuthService authService;

    @PostMapping("/signup")
    public ResponseEntity<ApiResponseDto<SimpleMessageResponseDto>> signup(@Valid @RequestBody SignUpRequestDto req) {
        SimpleMessageResponseDto data = authService.signup(req);
        return ResponseEntity
                .status(HttpStatus.CREATED)
                .body(ApiResponseDto.ok(data));
    }

    @PostMapping("/login")
    public ResponseEntity<ApiResponseDto<JwtResponseDto>> login(@Valid @RequestBody LoginRequestDto req) {
        JwtResponseDto data = authService.login(req);
        return ResponseEntity.ok(ApiResponseDto.ok(data));
    }

    @PostMapping("/logout")
    public ResponseEntity<ApiResponseDto<SimpleMessageResponseDto>> logout() {
        SimpleMessageResponseDto response = SimpleMessageResponseDto.of("로그아웃 성공.");
        return ResponseEntity.ok(ApiResponseDto.ok(response));
    }
}
