# -*- coding: utf-8 -*-
# @ProjectName: toolbox
# @FileName : obsidian_plugin_localization.py
# @Time     : 2023/6/8 18:45
# @Author   : lijun
# @Email    : 317152347@qq.com
# @Version  : 1.0.0
# @ProductName  : PyCharm


import glob
import multiprocessing
import os
import re
import shutil
import argparse
import time

import requests

from translate import Translator

translator = Translator(to_lang='zh')


# TODO 1. 需要将目标语种抽离到cli中，可进行修改
# TODO 2. 默认翻译有使用间隔，一段时间内长时间使用会提示限制，需要能切换到第二种tr方法，增加容错率
def operate_js(js_path):
    """
    操作传入的js文件，进行指定值的汉化翻译
    :param js_path:
    :type js_path:
    :return:
    :rtype:
    """
    back_file(js_path)

    with open(js_path, 'r') as f:
        js_content = f.read()
        # 兼容 setName("Show language name") setName(u"abc's") setName('English language')
        set_names = re.findall(r"setName\((?:u)?[\"']([^\"']+)[\"']\)", js_content)
        set_desc = re.findall(r"setDesc\((?:u)?[\"']([^\"']+)[\"']\)", js_content)

        js_dict = dict(zip(set_names, set_desc))
        a1 = 'AAA'
        for k, v in js_dict.items():
            try:
                if contains_only_alphanumeric_space_symbols(k):
                    if len(k) > 1:
                        #  更新替换方法，兼容单双引号问题
                        js_content = re.sub(r"setName\((u)?([\'\"])(.*)\2\)",
                                            f"setName(\\1\\2{translator.translate(k)}\\2)",
                                            js_content)
                        js_content = re.sub(r"setDesc\((u)?([\'\"])(.*)\2\)",
                                            f"setDesc(\\1\\2{translator.translate(v)}\\2)",
                                            js_content)
                    else:
                        print(f"Skip Translation：{js_path} 待翻译文本长度不足：{k} 跳过翻译")
                else:
                    print(f"Pause translation：{js_path} 包含非英文内容 「{k}」，暂不翻译")
            except Exception as e:
                print(f"错误的key：{k}")

    with open(js_path, 'w') as f:
        f.write(js_content)

    print(f'Modified and saved: {js_path}')


def tr(content):
    url = "https://translate.volcengine.com/crx/translate/v1"
    headers = {'Content-Type': 'application/json'}
    body = {
        "target_language": 'zh',
        "text": content
    }

    response = requests.post(url, headers=headers, json=body)
    result = response.json()['translation']
    print(f"old_content:{content}\t new_content:{result}\n")
    return result


def operate_js1(js_path):
    back_file(js_path)

    time.sleep(3)
    with open(js_path, 'r') as f:
        js_content = f.read()

        set_names = re.findall(r'setName\((?:u\()?"([^"]+)"(?:\))?\)', js_content)
        set_desc = re.findall(r'setDesc\((?:u\()?"([^"]+)"(?:\))?\)', js_content)

        js_dict = dict(zip(set_names, set_desc))

        print(js_dict)

        for k, v in js_dict.items():
            try:
                if len(k) > 1:
                    js_content = js_content.replace(f'setName("{k}")', f'setName("{tr(k)}")')
                    js_content = js_content.replace(f'setDesc("{v}")', f'setDesc("{tr(v)}")')
                else:
                    print(f"{js_path} 待翻译文本长度不足：{k} 跳过翻译")
            except Exception as e:
                print(f"错误的key：{k}")

    with open(js_path, 'w') as f:
        f.write(js_content)

    print(f'Modified and saved: {js_path}')


def search_js(directory):
    # 使用 glob 模块匹配所有的 main.js 文件路径
    file_paths = glob.glob(os.path.join(directory, '**', 'main.js'), recursive=True)

    return file_paths


def back_file(file_path):
    backup_path = file_path + '.bak'
    shutil.copy2(file_path, backup_path)


def process_files(directory):
    main_files = search_js(directory)

    if main_files:
        # 创建进程池并处理文件
        with multiprocessing.Pool() as pool:
            results = pool.map(operate_js, main_files)
    else:
        print("ERROR: 指定路径没有符合条件的main.js文件")


def parser_cli():
    # 创建 ArgumentParser 对象
    parser = argparse.ArgumentParser(prog='operators', formatter_class=argparse.RawDescriptionHelpFormatter)

    # 添加参数
    parser.add_argument('-fp', '--file_path', default="./plugins", help="Obsidian Plus插件路径,默认为脚本同级目录")

    return parser.parse_args()


def contains_only_alphanumeric_space_symbols(text):
    pattern = re.compile(r'^[a-zA-Z0-9\s!"#$%&\'()*+,-./:;<=>?@\[\\\]^_`{|}~]+$')
    return bool(re.match(pattern, text))


if __name__ == '__main__':
    print(f"========== 本程序只汉化 Obsidian应用 Plugins插件 ==========\n")

    file_path = parser_cli().file_path
    print(f"查找路径：{file_path}")

    process_files(file_path)
