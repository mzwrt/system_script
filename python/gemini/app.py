from quart import Quart, request, jsonify
import hashlib
import xml.etree.ElementTree as ET
import aiohttp
import asyncio
import json
import os
from dotenv import load_dotenv
from time import time

# 加载环境变量
load_dotenv()

app = Quart(__name__)

TOKEN = os.getenv('TOKEN', 'default_token')  # 从环境变量获取
ENCODE_AES_KEY = os.getenv('ENCODE_AES_KEY')  # 从环境变量获取
API_KEY = os.getenv('API_KEY')  # 从环境变量获取

GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"

# 验证消息来源
def check_signature(signature, timestamp, nonce):
    tmp_list = [TOKEN, timestamp, nonce]
    tmp_list.sort()
    tmp_str = ''.join(tmp_list)
    return hashlib.sha1(tmp_str.encode('utf-8')).hexdigest() == signature

# 异步获取 Gemini AI 的回复
async def get_gemini_ai_reply_async(user_msg):
    async with aiohttp.ClientSession() as session:
        headers = {'Content-Type': 'application/json'}
        payload = {
            "contents": [{
                "parts": [{"text": user_msg}]
            }]
        }
        
        # 发送请求到 Gemini API
        async with session.post(GEMINI_API_URL + "?key=" + API_KEY, headers=headers, json=payload) as response:
            if response.status == 200:
                response_json = await response.json()
                try:
                    ai_reply = response_json['candidates'][0]['content']['parts'][0]['text']
                    return ai_reply
                except KeyError as e:
                    return f"Error: Key '{e}' not found in response JSON."
            else:
                return "无法获取智能回复，请稍后再试。"

# 微信消息处理函数
async def process_message(user_msg):
    return await get_gemini_ai_reply_async(user_msg)

@app.route('/webhook', methods=['GET', 'POST'])
async def webhook():
    if request.method == 'GET':
        # 微信服务器验证
        signature = request.args.get('signature')
        timestamp = request.args.get('timestamp')
        nonce = request.args.get('nonce')
        if check_signature(signature, timestamp, nonce):
            return request.args.get('echostr')
        else:
            return "Invalid request"
    elif request.method == 'POST':
        # 处理微信发送的消息
        data = await request.data
        xml_data = ET.fromstring(data)
        msg_type = xml_data.find('MsgType').text

        # 根据不同的消息类型返回相应的回复
        if msg_type == 'text':
            user_msg = xml_data.find('Content').text
            # 异步调用获取 AI 回复
            response_msg = await process_message(user_msg)
            reply = generate_reply_xml(xml_data, response_msg)
            return reply
        elif msg_type == 'voice':
            response_msg = "抱歉！暂不支持语音消息。只支持文字消息！"
            reply = generate_reply_xml(xml_data, response_msg)
            return reply
        elif msg_type == 'image':
            response_msg = "抱歉！暂不支持图片消息。只支持文字消息！"
            reply = generate_reply_xml(xml_data, response_msg)
            return reply
        elif msg_type == 'video':
            response_msg = "抱歉！暂不支持视频消息。只支持文字消息！"
            reply = generate_reply_xml(xml_data, response_msg)
            return reply
        else:
            response_msg = "抱歉！不支持该类型的消息。只支持文字消息！"
            reply = generate_reply_xml(xml_data, response_msg)
            return reply

# 生成微信响应的 XML 数据
def generate_reply_xml(xml_data, response_msg):
    to_user = xml_data.find('FromUserName').text
    from_user = xml_data.find('ToUserName').text
    msg_id = str(int(time()))  # 使用时间戳作为消息 ID
    reply = f"""
    <xml>
        <ToUserName>{to_user}</ToUserName>
        <FromUserName>{from_user}</FromUserName>
        <CreateTime>{int(time())}</CreateTime>
        <MsgType>text</MsgType>
        <Content>{response_msg}</Content>
        <MsgId>{msg_id}</MsgId>
    </xml>
    """
    return reply

# 确保在 asyncio 事件循环中运行
if __name__ == '__main__':
    import asyncio
    from hypercorn.asyncio import serve
    from hypercorn.config import Config

    config = Config()
    config.bind = ["0.0.0.0:5000"]

    # 使用 asyncio 运行 Hypercorn
    asyncio.run(serve(app, config))
