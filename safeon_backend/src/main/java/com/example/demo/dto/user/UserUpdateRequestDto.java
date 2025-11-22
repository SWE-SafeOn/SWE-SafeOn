package com.example.demo.dto.user;

import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@NoArgsConstructor
public class UserUpdateRequestDto {

    private String name;
    private String password;

    public UserUpdateRequestDto(String name, String password) {
        this.name = name;
        this.password = password;
    }
}
