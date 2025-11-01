# build
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY UniScanner.Be.csproj ./
RUN dotnet restore UniScanner.Be.csproj
COPY . .
RUN dotnet publish UniScanner.Be.csproj -c Release -o /app /p:UseAppHost=false

# run
FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=build /app .
EXPOSE 45444
ENV ASPNETCORE_URLS=http://0.0.0.0:45444
ENTRYPOINT ["dotnet", "UniScanner.Be.dll"]
