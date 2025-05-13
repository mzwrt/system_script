from quart import Quart, request, Response
import hashlib
import xml.etree.ElementTree as ET
import aiohttp
import asyncio
import os
from dotenv import load_dotenv
from time import time
import html

# 加载环境变量
load_dotenv()

app = Quart(__name__)

# 配置安全变量（必须配置环境变量）
TOKEN = os.getenv('TOKEN')
ENCODE_AES_KEY = os.getenv('ENCODE_AES_KEY')
API_KEY = os.getenv('API_KEY')
if not TOKEN or not API_KEY:
    raise RuntimeError("请设置 TOKEN 和 API_KEY 环境变量")

GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"

# 校验签名
def check_signature(signature, timestamp, nonce):
    tmp_list = [TOKEN, timestamp, nonce]
    tmp_list.sort()
    tmp_str = ''.join(tmp_list)
    return hashlib.sha1(tmp_str.encode('utf-8')).hexdigest() == signature

# 获取 Gemini AI 回复
async def get_gemini_ai_reply_async(user_msg):
    try:
        async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=10)) as session:
            headers = {'Content-Type': 'application/json'}
            payload = {
                "contents": [{
                    "parts": [{"text": user_msg[:2000]}]  # 限制输入长度
                }]
            }

            async with session.post(
                f"{GEMINI_API_URL}?key={API_KEY}",
                headers=headers, json=payload
            ) as response:
                if response.status == 200:
                    response_json = await response.json()
                    # 获取 AI 回复内容
                    ai_reply = response_json.get('candidates', [{}])[0].get('content', {}).get('parts', [{}])[0].get('text', '无法解析 AI 回复')
                    
                    # 替换 "google" 和 "Google" 为 "MZmini"
                    ai_reply = ai_reply.replace("google", "china").replace("Google", "china")
                    
                    return ai_reply
                else:
                    return f"Gemini API 错误: {response.status}"
    except Exception as e:
        return f"内部错误: {str(e)}"

# 生成微信 XML 回复（HTML 安全编码）
def generate_reply_xml(xml_data, response_msg):
    def safe(tag):
        return html.escape(tag or "", quote=False)

    to_user = safe(xml_data.findtext('FromUserName'))
    from_user = safe(xml_data.findtext('ToUserName'))
    reply = f"""<xml>
    <ToUserName><![CDATA[{to_user}]]></ToUserName>
    <FromUserName><![CDATA[{from_user}]]></FromUserName>
    <CreateTime>{int(time())}</CreateTime>
    <MsgType><![CDATA[text]]></MsgType>
    <Content><![CDATA[{response_msg[:2048]}]]></Content>
</xml>"""
    return Response(reply, content_type='application/xml')

# 处理微信消息
@app.route('/webhook', methods=['GET', 'POST'])
async def webhook():
    try:
        if request.method == 'GET':
            # 微信服务器验证
            signature = request.args.get('signature')
            timestamp = request.args.get('timestamp')
            nonce = request.args.get('nonce')
            echostr = request.args.get('echostr')

            if all([signature, timestamp, nonce, echostr]) and check_signature(signature, timestamp, nonce):
                return Response(echostr)
            return Response("非法请求", status=403)

        elif request.method == 'POST':
            data = await request.data
            try:
                xml_data = ET.fromstring(data)
            except ET.ParseError:
                return Response("无效 XML", status=400)

            msg_type = xml_data.findtext('MsgType')
            if msg_type == 'text':
                user_msg = xml_data.findtext('Content', '')[:2000]
                ai_reply = await get_gemini_ai_reply_async(user_msg)
                return generate_reply_xml(xml_data, ai_reply)

            # 非文字消息统一回复
            return generate_reply_xml(xml_data, "抱歉！暂只支持文字消息。")

        return Response("不支持的方法", status=405)
    except Exception as e:
        return Response(f"内部错误: {str(e)}", status=500)

# 启动 Hypercorn
if __name__ == '__main__':
    from hypercorn.asyncio import serve
    from hypercorn.config import Config

    config = Config()
    config.bind = ["127.0.0.1:5000"]  # 内部监听，安全性更高
    config.worker_class = "asyncio"
    config.keep_alive_timeout = 10
    config.accesslog = "-"
    config.errorlog = "-"

    asyncio.run(serve(app, config))
