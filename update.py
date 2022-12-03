import click
import re
import os
import json
import requests
import subprocess
import psutil
from typing import Optional


def parse_version(s: str) -> (int, int, int):
    s = s.split(".")

    return (int(s[0]), int(s[1]), int(s[2]))


def parse_config(path: str) -> dict:
    with open(path) as f:
        raw = f.read()
        obj = json.loads(raw)

        return obj


def get_release_information(url: str, proxy: Optional[str]) -> dict:
    proxies = None
    if proxy is not None:
        proxies = {
            "http": proxy,
            "https": proxy
        }
    headers = requests.utils.default_headers()
    headers.update({
        "User-agent": "Mozilla/5.0"
    })

    response = requests.get(url, proxies=proxies, headers=headers)

    return response.json()


def get_current_version(path: str):
    p = subprocess.run(["Powershell.exe", "-Command",
                       f"(Get-Item \"{path}\").VersionInfo.FileVersion"], stdout=subprocess.PIPE)
    # p = subprocess.run(["ipconfig"], stdout=subprocess.PIPE)
    out = p.stdout

    return out.strip().decode("utf-8")


def get_download_url(assets: list, pat: str) -> str:
    it = filter(lambda i: re.match(pat, i["name"]), assets)
    asset = list(it)
    assert len(asset) == 1

    return asset[0]["browser_download_url"]


def download_file(f, url: str, proxy: Optional[str]):
    proxies = None
    if proxy is not None:
        proxies = {
            "http": proxy,
            "https": proxy
        }
    headers = requests.utils.default_headers()
    headers.update({
        "User-agent": "Mozilla/5.0"
    })

    response = requests.get(url, proxies=proxies, headers=headers)

    f.write(response.content)


def kill_process(path):
    file_name = os.path.basename(path)

    for proc in psutil.process_iter():
        # check whether the process name matches
        if proc.name() == file_name:
            proc.kill()


def extract_file(f, unzip, wd):
    os.chdir(wd)
    subprocess.run([unzip, "x", "-y", f])
