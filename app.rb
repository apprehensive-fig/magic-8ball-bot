# app.rb
require "sinatra"
require "json"
require "net/http"
require "uri"
require "tempfile"

require "line/bot"
require "ibm_watson/visual_recognition_v3"

include IBMWatson

def client
  @client ||= Line::Bot::Client.new { |config|
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_ACCESS_TOKEN"]
  }
end

def bot_answer_to(a_question)
  if a_question.match?(/(Hi|Hey|Bonjour|Hi there|Hey there|Hello).*/i)
    "Hello " + user_name + ", how are you doing today?"
  elsif a_question.match?(/how\s+.*are\s+.*you.*/i)
    "I am fine, " + user_name
  elsif a_question.match?(/.*le wagon.*/i)
    "Wait " + user_name + "... you want to know about Le Wagon Kyoto!? These guys are just great!"
  elsif a_question.end_with?('?')
    "Good question, " + user_name + "!"
  else
    ["I couldn't agree more", "Great to hear that", "Kinda make sense"].sample
  end
end

post "/callback" do
  body = request.body.read

  signature = request.env["HTTP_X_LINE_SIGNATURE"]
  unless client.validate_signature(body, signature)
    error 400 do "Bad Request" end
  end

  events = client.parse_events_from(body)
  events.each { |event|
    case event
    # Text recognition using REGEX and vanilla Ruby
    when Line::Bot::Event::Message
      case event.type
      when Line::Bot::Event::MessageType::Text
        p event
        user_id = event["source"]["userId"]
        user_name = ""

        response = client.get_profile(user_id)
        case response
        when Net::HTTPSuccess then
          contact = JSON.parse(response.body)
          p contact
          user_name = contact["displayName"]
        else
          p "#{response.code} #{response.body}"
        end

        # The answer mecanism is here!
        message = {
          type: "text",
          text: bot_answer_to(event.message["text"])
        }
        client.reply_message(event["replyToken"], message)

        p 'One more message!'
        p event["replyToken"]
        p message
        p client

      # Image recognition
      when Line::Bot::Event::MessageType::Image
        response_image = client.get_message_content(event.message["id"])
        tf = Tempfile.open
        tf.write(response_image.body)

        # Using IBM Watson visual recognition API
        visual_recognition = VisualRecognitionV3.new(
          version: "2018-03-19",
          iam_apikey: ENV["IBM_IAM_API_KEY"]
        )

        image_result = ""
        File.open(tf.path) do |images_file|
          classes = visual_recognition.classify(
            images_file: images_file,
            threshold: "0.6"
          )
          image_result = p classes.result["images"][0]["classifiers"][0]["classes"]
        end
        # # Sending the results
        message = {
          type: "text",
          text: "I think it remind me of a #{image_result[0]["class"].capitalize} thing or maybe... #{image_result[1]["class"].capitalize}?? or some words like that... let say #{image_result[2]["class"].capitalize}, am I right?"
        }

        client.reply_message(event["replyToken"], message)
        tf.unlink
      end
    end
  }

  "OK"
end
