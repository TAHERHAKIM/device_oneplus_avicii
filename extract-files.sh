#!/bin/bash
#
# SPDX-FileCopyrightText: 2016 The CyanogenMod Project
# SPDX-FileCopyrightText: 2017-2024 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

set -e

DEVICE=avicii
VENDOR=oneplus

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

ANDROID_ROOT="${MY_DIR}/../../.."

# If XML files don't have comments before the XML header, use this flag
# Can still be used with broken XML files by using blob_fixup
export TARGET_DISABLE_XML_FIXING=true

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

ONLY_FIRMWARE=
KANG=
SECTION=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        --only-common)
            ONLY_COMMON=true
            ;;
        --only-firmware)
            ONLY_FIRMWARE=true
            ;;
        --only-target)
            ONLY_TARGET=true
            ;;
        -n | --no-cleanup)
            CLEAN_VENDOR=false
            ;;
        -k | --kang)
            KANG="--kang"
            ;;
        -s | --section)
            SECTION="${2}"
            shift
            CLEAN_VENDOR=false
            ;;
        *)
            SRC="${1}"
            ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

function blob_fixup() {
    case "${1}" in
        odm/bin/hw/vendor.oplus.hardware.biometrics.fingerprint@2.1-service)
            [ "$2" = "" ] && return 0
            grep -q libshims_fingerprint.oplus.so "${2}" || "${PATCHELF}" --add-needed libshims_fingerprint.oplus.so "${2}"
            ;;
        odm/etc/vintf/manifest/manifest_oplus_fingerprint.xml)
            [ "$2" = "" ] && return 0
            sed -ni "/android.hardware.biometrics.fingerprint/{x;s/hal format/hal override=\"true\" format/;x};x;1!p;\${x;p}" "${2}"
            ;;
        odm/lib64/libwvhidl.so)
            [ "$2" = "" ] && return 0
            grep -q "libcrypto_shim.so" "${2}" || "${PATCHELF}" --add-needed "libcrypto_shim.so" "${2}"
            ;;
        odm/lib64/mediadrm/libwvdrmengine.so)
            [ "$2" = "" ] && return 0
            grep -q "libcrypto_shim.so" "${2}" || "${PATCHELF}" --add-needed "libcrypto_shim.so" "${2}"
            ;;
        product/app/PowerOffAlarm/PowerOffAlarm.apk)
            [ "$2" = "" ] && return 0
            apktool_patch "${2}" "${MY_DIR}/blob-patches/PowerOffAlarm.patch" -s
            ;;
        product/etc/sysconfig/com.android.hotwordenrollment.common.util.xml)
            [ "$2" = "" ] && return 0
            sed -i "s/\/my_product/\/product/" "${2}"
            ;;
        system_ext/framework/oplus-ims-ext.jar)
            [ "$2" = "" ] && return 0
            apktool_patch "${2}" "${MY_DIR}/blob-patches/oplus-ims-ext.patch" -r
            ;;
        system_ext/lib64/libwfdnative.so)
            [ "$2" = "" ] && return 0
            sed -i "s/android.hidl.base@1.0.so/libhidlbase.so\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00/" "${2}"
            ;;
        vendor/etc/libnfc-nci.conf)
            [ "$2" = "" ] && return 0
            sed -i "s/NFC_DEBUG_ENABLED=0x01/NFC_DEBUG_ENABLED=0x00/" "${2}"
            ;;
        vendor/etc/libnfc-nxp.conf)
            [ "$2" = "" ] && return 0
            sed -i "/NXP_NFC_DEV_NODE/ s/pn553/nq-nci/" "${2}"
            sed -i "/NXPLOG_\w\+_LOGLEVEL/ s/0x03/0x02/" "${2}"
            sed -i "s/NFC_DEBUG_ENABLED=0x01/NFC_DEBUG_ENABLED=0x00/" "${2}"
            ;;
        vendor/lib64/hw/com.qti.chi.override.so)
            [ "$2" = "" ] && return 0
            grep -q libcamera_metadata_shim.so "${2}" || "${PATCHELF}" --add-needed libcamera_metadata_shim.so "${2}"
            sed -i "s/com.oem.autotest/\x00om.oem.autotest/" "${2}"
            ;;
        vendor/lib64/sensors.ssc.so)
            [ "$2" = "" ] && return 0
            sed -i "s/qti.sensor.wise_light/android.sensor.light\x00/" "${2}"
            "${SIGSCAN}" -p "F1 E9 D3 84 52 49 3F A0 72" -P "F1 A9 00 80 52 09 00 A0 72" -f "${2}"
            ;;
        vendor/lib64/vendor.qti.hardware.camera.postproc@1.0-service-impl.so)
            [ "$2" = "" ] && return 0
            "${SIGSCAN}" -p "53 0A 00 94" -P "1F 20 03 D5" -f "${2}"
            ;;
    esac

    return 0
}

function blob_fixup_dry() {
    blob_fixup "$1" ""
}

# Initialize the helper
setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

if [ -z "${ONLY_FIRMWARE}" ]; then
    extract "${MY_DIR}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"
fi

extract_firmware "${MY_DIR}/proprietary-firmware.txt" "${SRC}"

"${MY_DIR}/setup-makefiles.sh"
