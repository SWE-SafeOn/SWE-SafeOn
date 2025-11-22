package com.example.demo.exception;

/**
 * 도메인 수준에서 접근 권한이 없을 때 사용되는 예외.
 */
public class AccessDeniedException extends RuntimeException {
    public AccessDeniedException(String message) {
        super(message);
    }
}
