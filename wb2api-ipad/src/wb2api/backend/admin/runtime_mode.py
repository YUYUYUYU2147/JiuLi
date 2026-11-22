import os


def is_embedded_mobile() -> bool:
    return os.getenv("WORKBUDDY_ANDROID") == "1" or os.getenv("WORKBUDDY_IOS") == "1"


def is_android() -> bool:
    return os.getenv("WORKBUDDY_ANDROID") == "1"


