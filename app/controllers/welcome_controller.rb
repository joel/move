# frozen_string_literal: true

class WelcomeController < ApplicationController
  def home
    render Views::Welcome::Home.new
  end
end
