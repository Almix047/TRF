# Модели
class PromoMessage < ActiveRecord::Base
end

class User < ActiveRecord::Base
  has_many :ads
  scope :recent, -> { order(created_at: :desc) }
end

class Ad < ActiveRecord::Base
  belongs_to :user
end




# Контроллеры
class PromoMessagesController < ApplicationController
  def new
    @message = PromoMessage.new
    @sample_of_users = SampleOfUsersService.call(params[:date_from], params[:date_to], params[:page])
  end

  def create
    @message = PromoMessage.new(promo_message_params)

    recipients = @sample_of_users.pluck(:phone)

    if @message.save
      SendPromoMessageService.send_message(recipients)
      redirect_to promo_messages_path, notice: 'Messages scheduled for sending.'
    else
      render 'new', alert: 'Something went wrong'
    end
  end

  def download_csv
    CsvReportService.new.call(params[:date_from], params[:date_to], params[:page])
  end

  private

  def promo_message_params
    params.permit(:body, :date_from, :date_to)
  end
end




# Сервисы
class SampleOfUsersService
  def self.call(date_from, date_to, page)
    if valid_date?(date_from) && valid_date?(date_to)
      User.recent.joins(:ads).where('published_ads_count': 1)
          .where('published_at': date_from..date_to)
          .page(page)
    end
  end

  private

  def valid_date?(date)
    date.present? && (Date.parse(date) rescue nil).is_a?(Date)
  end
end

class CsvReportService
  ATTRIBUTES = %w[id phone name].freeze

  def call(date_from, date_to, page)
    users = SampleOfUsersService.call(date_from, date_to, page)
    send_data to_csv(users), filename: "promotion-users-#{Time.zone.today}.csv"
  end

  private

  def to_csv(data)
    CSV.generate(headers: true) do |csv|
      csv << ATTRIBUTES
      data.each do |user|
        csv << ATTRIBUTES.map { |attr| user.send(attr) }
      end
    end
  end
end

class SendPromoMessageService
  def send_message(recipients)
    recipients.each.slice(1000) { |r| PromoMessagesSendJob.perform_later(r) }
  end
end
