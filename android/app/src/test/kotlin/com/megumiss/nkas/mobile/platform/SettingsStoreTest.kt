package com.megumiss.nkas.mobile.platform

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 默认 Docker 镜像决定初始化时 proot-distro 从哪里拉取 NKAS 容器，
 * 改动会影响所有首次安装的用户，用测试固定住取值与格式。
 */
class SettingsStoreTest {
    @Test
    fun defaultDockerImageUsesTheOfficialRegistry() {
        assertEquals("docker.io/megumiss/nkas:latest", SettingsStore.DEFAULT_DOCKER_IMAGE)
        assertTrue(
            "默认镜像必须指向官方源",
            SettingsStore.DEFAULT_DOCKER_IMAGE.startsWith("docker.io/"),
        )
    }

    @Test
    fun defaultDockerImagePassesNativeValidation() {
        // 与 NkasPlatformBridge.saveInitConfig 的校验保持一致，
        // 否则用户直接保存默认值就会被判为格式错误
        assertTrue(
            SettingsStore.DEFAULT_DOCKER_IMAGE.matches(Regex("[A-Za-z0-9._/-]+:[A-Za-z0-9._-]+")),
        )
    }

    @Test
    fun defaultDockerImagePassesBootstrapShellGuard() {
        // bootstrap.sh 的 install_container 会拒绝白名单以外的字符
        assertTrue(SettingsStore.DEFAULT_DOCKER_IMAGE.none { it !in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:/-" })
    }
}
