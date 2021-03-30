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
  before_action :users, only: [:new, :create]

  def new
    @message = PromoMessage.new
  end

  def create
    @message = PromoMessage.new(promo_message_params)

    if @message.save
      SendPromoMessageService.send_message(@users.select(:phone))
      redirect_to promo_messages_path, notice: 'Messages scheduled for sending.'
    else
      render 'new', alert: 'Something went wrong'
    end
  end

  def download_csv
    users
    send_data CsvReportService.to_csv(users), filename: "promotion-users-#{Time.zone.today}.csv"
  end

  private

  def users
    if valid_date?(params[:date_from]) && valid_date?(params[:date_to])
      @users = UsersService.call(params[:date_from], params[:date_to], params[:page])
    end
  end

  def valid_date?(date)
    date.present? && (Date.parse(date) rescue nil).is_a?(Date)
  end

  def promo_message_params
    params.permit(:body, :date_from, :date_to)
  end
end




# Сервисы
class UsersService
  def self.call(date_from, date_to, page)
      User.joins(:ads)
          .where('published_ads_count': 1, 'published_at': date_from..date_to)
          .recent.page(page)
    end
  end
end

class CsvReportService
  ATTRIBUTES = %w[id phone name].freeze

  def self.to_csv(data)
    CSV.generate(headers: true) do |csv|
      csv << ATTRIBUTES
      data.each do |user|
        csv << ATTRIBUTES.map { |attr| user.public_send(attr) }
      end
    end
  end
end

class SendPromoMessageService
  def self.send_message(recipients)
    recipients.find_each { |r| PromoMessagesSendJob.perform_later(r) }
  end
end
