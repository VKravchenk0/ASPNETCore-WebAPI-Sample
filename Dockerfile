# Stage 1: Build
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

COPY SampleWebApiAspNetCore/SampleWebApiAspNetCore.csproj SampleWebApiAspNetCore/
RUN dotnet restore SampleWebApiAspNetCore/SampleWebApiAspNetCore.csproj

COPY . .
RUN dotnet publish SampleWebApiAspNetCore/SampleWebApiAspNetCore.csproj \
    -c Release \
    -o /app/publish \
    --no-restore

# Stage 2: Runtime
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS final
WORKDIR /app

COPY --from=build /app/publish .

ENV ASPNETCORE_ENVIRONMENT=Development

EXPOSE 8080

CMD ["sh", "-c", "dotnet SampleWebApiAspNetCore.dll --urls http://+:${PORT:-8080}"]
