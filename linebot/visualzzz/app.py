import os
import requests
from flask import Flask, request, abort
import psycopg2

from linebot import (
    LineBotApi, WebhookHandler
)
from linebot.exceptions import (
    InvalidSignatureError
)
from linebot.models import (
    MessageEvent, TextMessage, TextSendMessage, LocationSendMessage,
)

app = Flask(__name__)

ACCESS_TOKEN = os.environ.get('ACCESS_TOKEN')
SECRET = os.environ.get('SECRET')

line_bot_api = LineBotApi(ACCESS_TOKEN)
handler = WebhookHandler(SECRET)

DATABASE_URL = "postgres://zinizeytsnxcya:78ff4cdc2905a569139a86f13f5a7078e4c3c7fd008b040a548ee380ba5b7f68@ec2-107-22-83-3.compute-1.amazonaws.com:5432/d3676fnidddhst"


@app.route("/sos", methods=['POST'])
def sos():
    user_id = request.form.get('user_id')
    name = request.form.get('name')
    lat = request.form.get('lat')
    lng = request.form.get('long')
    dtime = request.form.get('dtime')

    res = name+' 發生跌倒!'

    location_message = LocationSendMessage(
        title=name+' 發生跌倒!',
        address=dtime,
        latitude=lat,
        longitude=lng
    )

    line_bot_api.push_message(user_id, TextSendMessage(text=res))
    line_bot_api.push_message(user_id, location_message)

    return 'OK'


@app.route("/callback", methods=['POST'])
def callback():
    # get X-Line-Signature header value
    signature = request.headers['X-Line-Signature']

    # get request body as text
    body = request.get_data(as_text=True)
    app.logger.info("Request body: " + body)

    # handle webhook body
    try:
        handler.handle(body, signature)
    except InvalidSignatureError:
        abort(400)

    return 'OK'


@handler.add(MessageEvent, message=TextMessage)
def handle_message(event):
    msg = event.message.text
    if msg == "取得ID":
        user_id = str(event.source.user_id)
        res = "請將以下ID複製至App進行綁定"
        line_bot_api.reply_message(
            event.reply_token,
            TextSendMessage(text=res))
        line_bot_api.push_message(user_id, TextSendMessage(text=user_id))


if __name__ == "__main__":
    app.run()
